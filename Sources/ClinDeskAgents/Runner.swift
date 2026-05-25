import Foundation

public enum Runner {
    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        previousResponseID: String? = nil,
        autoPreviousResponseID: Bool = false,
        conversationID: String? = nil,
        session: (any Session)? = nil
    ) async throws -> RunResult {
        try await run(
            agent: agent,
            input: [.message(AgentMessage(role: .user, content: input))],
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            previousResponseID: previousResponseID,
            autoPreviousResponseID: autoPreviousResponseID,
            conversationID: conversationID,
            session: session
        )
    }

    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        previousResponseID: String? = nil,
        autoPreviousResponseID: Bool = false,
        conversationID: String? = nil,
        session: (any Session)? = nil
    ) async throws -> RunResult {
        var resolvedConfig = runConfig
        if let maxTurns {
            resolvedConfig.maxTurns = maxTurns
        }
        if let hooks {
            resolvedConfig.hooks = hooks
        }
        if let previousResponseID {
            resolvedConfig.previousResponseID = previousResponseID
        }
        if autoPreviousResponseID {
            resolvedConfig.autoPreviousResponseID = true
        }
        if let conversationID {
            resolvedConfig.conversationID = conversationID
        }
        if let session {
            resolvedConfig.session = session
        }
        let loop = RunnerLoop(
            startingAgent: agent,
            input: input,
            contextValue: context,
            modelProvider: modelProvider,
            config: resolvedConfig
        )
        return try await loop.run()
    }

    public static func runStream<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        previousResponseID: String? = nil,
        autoPreviousResponseID: Bool = false,
        conversationID: String? = nil,
        session: (any Session)? = nil
    ) -> AsyncThrowingStream<RunStreamEvent<Context>, Error> {
        AsyncThrowingStream { continuation in
            var config = runConfig
            if let maxTurns {
                config.maxTurns = maxTurns
            }
            if let hooks {
                config.hooks = hooks
            }
            if let previousResponseID {
                config.previousResponseID = previousResponseID
            }
            if autoPreviousResponseID {
                config.autoPreviousResponseID = true
            }
            if let conversationID {
                config.conversationID = conversationID
            }
            if let session {
                config.session = session
            }
            let existingHooks = config.hooks
            config.hooks = RunHooks(
                onAgentStart: { agent in
                    continuation.yield(.agentStarted(agent))
                    existingHooks.onAgentStart(agent)
                },
                onModelStart: { agent in
                    continuation.yield(.modelStarted(agent))
                    existingHooks.onModelStart(agent)
                },
                onModelEnd: { response in
                    continuation.yield(.modelCompleted(response))
                    existingHooks.onModelEnd(response)
                },
                onToolStart: { tool, call in
                    continuation.yield(.toolStarted(tool, call))
                    existingHooks.onToolStart(tool, call)
                },
                onToolEnd: { output in
                    continuation.yield(.toolCompleted(output))
                    existingHooks.onToolEnd(output)
                },
                onHandoff: { handoff in
                    continuation.yield(.handoff(handoff))
                    existingHooks.onHandoff(handoff)
                },
                onGuardrail: { name, output in
                    continuation.yield(.guardrail(name, output))
                    existingHooks.onGuardrail(name, output)
                },
                onFinalOutput: { output in
                    continuation.yield(.finalOutput(output))
                    existingHooks.onFinalOutput(output)
                }
            )
            Task {
                do {
                    _ = try await run(
                        agent: agent,
                        input: input,
                        context: context,
                        modelProvider: modelProvider,
                        runConfig: config
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct RunnerLoop<Context: Sendable> {
    let startingAgent: Agent<Context>
    let input: [ModelInputItem]
    let contextValue: Context?
    let modelProvider: (any ModelProvider)?
    let config: RunConfig<Context>

    func run() async throws -> RunResult {
        try validateConfig()

        let runContext = RunContext(context: contextValue)
        var trace = Trace(
            id: config.traceID ?? UUID().uuidString,
            workflowName: config.workflowName,
            groupID: config.groupID,
            metadata: config.traceMetadata,
            includeSensitiveData: config.traceIncludeSensitiveData
        )

        var currentAgent = startingAgent
        var modelInput = try await prepareInitialInput()
        var newItems = input
        var lastResponseID: String?
        var explicitPreviousResponseID = config.previousResponseID

        try await runInputGuardrails(
            agent: currentAgent,
            context: runContext,
            input: modelInput,
            trace: &trace
        )

        var turn = 0
        while config.maxTurns == nil || turn < (config.maxTurns ?? 0) {
            turn += 1
            try runContext.throwingIfCancelled()
            trace.items.append(.agentStarted(currentAgent.name))
            config.hooks.onAgentStart(currentAgent)

            let tools = try await enabledTools(for: currentAgent, context: runContext)
            let handoffs = try await enabledHandoffs(for: currentAgent, context: runContext)
            let model = try await resolveModel(for: currentAgent)
            let instructions = try await currentAgent.instructions?.resolve(context: runContext, agent: currentAgent)
            let settings = currentAgent.modelSettings.merging(config.modelSettings)
            let modelInputData = try await filteredModelInputData(
                agent: currentAgent,
                context: runContext,
                input: modelInput,
                instructions: instructions
            )

            config.hooks.onModelStart(currentAgent)
            trace.items.append(.modelRequest(currentAgent.name))
            let response = try await model.getResponse(ModelRequest(
                instructions: modelInputData.instructions,
                input: modelInputData.input,
                context: runContext,
                settings: settings,
                tools: tools.map(\.descriptor),
                handoffs: handoffs.map(\.descriptor),
                outputSchema: currentAgent.outputSchema,
                previousResponseID: explicitPreviousResponseID ?? (config.autoPreviousResponseID ? lastResponseID : nil),
                conversationID: config.conversationID,
                tracing: modelTracing
            ))
            explicitPreviousResponseID = nil
            lastResponseID = response.id
            trace.items.append(.modelResponse(response))
            config.hooks.onModelEnd(response)

            modelInput = modelInputData.input
            let outputInputItems = response.output.map(Self.inputItem(from:))
            modelInput.append(contentsOf: outputInputItems)
            newItems.append(contentsOf: outputInputItems)

            if let handoffCall = response.functionCalls.first(where: { call in
                handoffs.contains { $0.descriptor.toolName == call.name }
            }) {
                guard let handoff = handoffs.first(where: { $0.descriptor.toolName == handoffCall.name }) else {
                    throw AgentsError.invalidModelResponse("Handoff call could not be resolved.")
                }
                config.hooks.onHandoff(handoff)
                trace.items.append(.handoff(handoff.descriptor.toolName))
                currentAgent = handoff.agent
                if let inputFilter = handoff.inputFilter ?? config.handoffInputFilter {
                    if usesServerManagedConversation {
                        throw AgentsError.invalidRunConfig(
                            "Server-managed conversations do not support handoff input filters."
                        )
                    }
                    modelInput = try await inputFilter(modelInput)
                }
                continue
            }

            let toolCalls = response.functionCalls.filter { call in
                tools.contains { $0.descriptor.name == call.name }
            }

            let unknownCalls = response.functionCalls.filter { call in
                !tools.contains { $0.descriptor.name == call.name }
                    && !handoffs.contains { $0.descriptor.toolName == call.name }
            }
            if let unknown = unknownCalls.first {
                switch config.toolNotFoundBehavior {
                case .throwError:
                    throw AgentsError.toolNotFound(unknown.name)
                case .returnErrorToModel:
                    let output = FunctionCallOutput(
                        callID: unknown.callID,
                        output: .string("Tool '\(unknown.name)' is not available.")
                    )
                    modelInput.append(.functionCallOutput(output))
                    newItems.append(.functionCallOutput(output))
                    trace.items.append(.toolResult(output))
                    continue
                }
            }

            if !toolCalls.isEmpty {
                let results = try await runToolCalls(
                    toolCalls,
                    tools: tools,
                    context: runContext,
                    trace: &trace
                )
                let outputs = results.map { FunctionCallOutput(callID: $0.call.callID, output: $0.output.modelValue) }
                let outputItems = outputs.map(ModelInputItem.functionCallOutput)
                modelInput.append(contentsOf: outputItems)
                newItems.append(contentsOf: outputItems)

                if let finalOutput = try await resolveToolUseBehavior(
                    currentAgent.toolUseBehavior,
                    context: runContext,
                    results: results
                ) {
                    return try await finish(
                        finalOutput,
                        agent: currentAgent,
                        context: runContext,
                        trace: &trace,
                        newItems: newItems,
                        responseID: lastResponseID
                    )
                }
                continue
            }

            let finalOutput = response.outputText
            return try await finish(
                finalOutput,
                agent: currentAgent,
                context: runContext,
                trace: &trace,
                newItems: newItems,
                responseID: lastResponseID
            )
        }

        throw AgentsError.maxTurnsExceeded(config.maxTurns ?? turn)
    }

    private var modelTracing: ModelTracing {
        if config.tracingDisabled {
            return .disabled
        }
        return config.traceIncludeSensitiveData ? .enabled(includeData: true) : .enabled(includeData: false)
    }

    private var usesServerManagedConversation: Bool {
        config.previousResponseID != nil || config.autoPreviousResponseID || config.conversationID != nil
    }

    private func validateConfig() throws {
        if let maxTurns = config.maxTurns, maxTurns < 1 {
            throw AgentsError.invalidRunConfig("maxTurns must be at least 1.")
        }
        if config.session != nil, usesServerManagedConversation {
            throw AgentsError.invalidRunConfig(
                "Session memory cannot be combined with previousResponseID, autoPreviousResponseID, or conversationID."
            )
        }
        if let limit = config.toolExecution.maxFunctionToolConcurrency, limit < 1 {
            throw AgentsError.invalidRunConfig("toolExecution.maxFunctionToolConcurrency must be at least 1.")
        }
    }

    private func prepareInitialInput() async throws -> [ModelInputItem] {
        guard let session = config.session else {
            return input
        }
        let history = try await session.getItems()
        guard let callback = config.sessionInputCallback else {
            return history + input
        }
        return try await callback(history, input)
    }

    private func filteredModelInputData(
        agent: Agent<Context>,
        context: RunContext<Context>,
        input: [ModelInputItem],
        instructions: String?
    ) async throws -> ModelInputData {
        let modelData = ModelInputData(input: input, instructions: instructions)
        guard let filter = config.callModelInputFilter else {
            return modelData
        }
        return try await filter(CallModelData(
            modelData: modelData,
            agent: agent,
            context: context.context
        ))
    }

    private func finish(
        _ output: String,
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        newItems: [ModelInputItem],
        responseID: String?
    ) async throws -> RunResult {
        try await runOutputGuardrails(agent: agent, context: context, output: output, trace: &trace)
        trace.items.append(.finalOutput(output))
        trace.endedAt = Date()
        config.hooks.onFinalOutput(output)
        if let session = config.session {
            try await session.addItems(newItems)
        }
        if !config.tracingDisabled {
            for processor in config.tracingProcessors {
                await processor.process(trace)
            }
        }
        return RunResult(
            finalOutput: output,
            lastAgentName: agent.name,
            trace: trace,
            newItems: newItems,
            responseID: responseID
        )
    }

    private func resolveModel(for agent: Agent<Context>) async throws -> any Model {
        if let model = config.model {
            return model
        }
        if let model = agent.model {
            return model
        }
        if let modelProvider {
            return try await modelProvider.model(named: config.modelName ?? agent.modelName)
        }
        throw AgentsError.missingModel(agentName: agent.name)
    }

    private func enabledTools(
        for agent: Agent<Context>,
        context: RunContext<Context>
    ) async throws -> [FunctionTool<Context>] {
        var enabled: [FunctionTool<Context>] = []
        for tool in agent.tools where await tool.isEnabled(context) {
            enabled.append(tool)
        }
        return enabled
    }

    private func enabledHandoffs(
        for agent: Agent<Context>,
        context: RunContext<Context>
    ) async throws -> [Handoff<Context>] {
        var enabled: [Handoff<Context>] = []
        for handoff in agent.handoffs where await handoff.isEnabled(context) {
            enabled.append(handoff)
        }
        return enabled
    }

    private func runInputGuardrails(
        agent: Agent<Context>,
        context: RunContext<Context>,
        input: [ModelInputItem],
        trace: inout Trace
    ) async throws {
        for guardrail in configInputGuardrails(for: agent) {
            let output = try await guardrail.run(context: context, agent: agent, input: input)
            config.hooks.onGuardrail(guardrail.name, output)
            if output.tripwireTriggered {
                trace.items.append(.guardrail(guardrail.name))
                throw AgentsError.inputGuardrailTripwire(name: guardrail.name, reason: output.outputInfo)
            }
        }
    }

    private func runOutputGuardrails(
        agent: Agent<Context>,
        context: RunContext<Context>,
        output: String,
        trace: inout Trace
    ) async throws {
        for guardrail in agent.outputGuardrails + config.outputGuardrails {
            let result = try await guardrail.run(context: context, agent: agent, output: output)
            config.hooks.onGuardrail(guardrail.name, result)
            if result.tripwireTriggered {
                trace.items.append(.guardrail(guardrail.name))
                throw AgentsError.outputGuardrailTripwire(name: guardrail.name, reason: result.outputInfo)
            }
        }
    }

    private func configInputGuardrails(for agent: Agent<Context>) -> [InputGuardrail<Context>] {
        agent.inputGuardrails + config.inputGuardrails
    }

    private func runToolCalls(
        _ calls: [FunctionCall],
        tools: [FunctionTool<Context>],
        context: RunContext<Context>,
        trace: inout Trace
    ) async throws -> [ToolRunResult] {
        var scheduled: [(offset: Int, tool: FunctionTool<Context>, call: FunctionCall)] = []
        for (offset, call) in calls.enumerated() {
            guard let tool = tools.first(where: { $0.descriptor.name == call.name }) else {
                throw AgentsError.toolNotFound(call.name)
            }
            trace.items.append(.toolCall(call))
            config.hooks.onToolStart(tool, call)
            scheduled.append((offset, tool, call))
        }

        guard !scheduled.isEmpty else {
            return []
        }

        let maxConcurrency = min(
            config.toolExecution.maxFunctionToolConcurrency ?? scheduled.count,
            scheduled.count
        )
        var orderedResults = Array<ToolRunResult?>(repeating: nil, count: scheduled.count)

        return try await withThrowingTaskGroup(of: (Int, ToolRunResult, FunctionCallOutput).self) { group in
            var nextIndex = 0

            func submitNext() {
                let job = scheduled[nextIndex]
                nextIndex += 1
                group.addTask {
                    let result = try await executeToolCall(tool: job.tool, call: job.call, context: context)
                    let output = FunctionCallOutput(callID: job.call.callID, output: result.output.modelValue)
                    return (job.offset, result, output)
                }
            }

            for _ in 0..<maxConcurrency {
                submitNext()
            }

            while let (offset, result, callOutput) = try await group.next() {
                orderedResults[offset] = result
                trace.items.append(.toolResult(callOutput))
                config.hooks.onToolEnd(callOutput)
                if nextIndex < scheduled.count {
                    submitNext()
                }
            }

            var results: [ToolRunResult] = []
            for result in orderedResults {
                guard let result else {
                    throw AgentsError.invalidModelResponse("Function tool result was not produced.")
                }
                results.append(result)
            }
            return results
        }
    }

    private func executeToolCall(
        tool: FunctionTool<Context>,
        call: FunctionCall,
        context: RunContext<Context>
    ) async throws -> ToolRunResult {
        let toolContext = ToolContext(runContext: context, call: call)

        if let approval = tool.approval {
            let approved = try await approval(ToolApprovalRequest(context: context, tool: tool.descriptor, call: call))
            guard approved else {
                throw AgentsError.approvalRejected(toolName: tool.descriptor.name)
            }
        }

        for guardrail in tool.inputGuardrails {
            let output = try await guardrail.run(context: toolContext)
            config.hooks.onGuardrail(guardrail.name, output)
            if output.tripwireTriggered {
                throw AgentsError.toolInputRejected(toolName: tool.descriptor.name, reason: output.outputInfo)
            }
        }

        let output = try await tool.run(toolContext)

        for guardrail in tool.outputGuardrails {
            let result = try await guardrail.run(context: toolContext, output: output)
            config.hooks.onGuardrail(guardrail.name, result)
            if result.tripwireTriggered {
                throw AgentsError.toolOutputRejected(toolName: tool.descriptor.name, reason: result.outputInfo)
            }
        }

        return ToolRunResult(call: call, output: output)
    }

    private func resolveToolUseBehavior(
        _ behavior: ToolUseBehavior<Context>,
        context: RunContext<Context>,
        results: [ToolRunResult]
    ) async throws -> String? {
        switch behavior {
        case .runModelAgain:
            return nil
        case .stopOnFirstTool:
            return results.first?.output.finalOutputText
        case .stopAtTools(let names):
            return results.first { names.contains($0.call.name) }?.output.finalOutputText
        case .custom(let resolver):
            let result = try await resolver(context, results)
            guard result.isFinalOutput else {
                return nil
            }
            return result.finalOutput ?? results.first?.output.finalOutputText ?? ""
        }
    }

    private static func inputItem(from output: ModelOutputItem) -> ModelInputItem {
        switch output {
        case .message(let message):
            return .message(message)
        case .functionCall(let call):
            return .functionCall(call)
        case .reasoning(let value):
            return .reasoning(value)
        case .raw(let value):
            return .raw(value)
        }
    }
}
