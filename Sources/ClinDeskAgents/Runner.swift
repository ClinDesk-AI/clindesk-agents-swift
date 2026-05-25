import Foundation

public enum Runner {
    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig()
    ) async throws -> RunResult {
        try await run(
            agent: agent,
            input: [.message(AgentMessage(role: .user, content: input))],
            context: context,
            modelProvider: modelProvider,
            runConfig: runConfig
        )
    }

    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig()
    ) async throws -> RunResult {
        let loop = RunnerLoop(
            startingAgent: agent,
            input: input,
            contextValue: context,
            modelProvider: modelProvider,
            config: runConfig
        )
        return try await loop.run()
    }

    public static func runStream<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig()
    ) -> AsyncThrowingStream<RunStreamEvent<Context>, Error> {
        AsyncThrowingStream { continuation in
            var config = runConfig
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
        let runContext = RunContext(context: contextValue)
        var trace = Trace(
            id: config.traceID ?? UUID().uuidString,
            workflowName: config.workflowName,
            groupID: config.groupID,
            metadata: config.traceMetadata,
            includeSensitiveData: config.traceIncludeSensitiveData
        )

        var currentAgent = startingAgent
        var modelInput = try await (config.session?.getItems() ?? []) + input
        var newItems = input
        var lastResponseID: String?

        try await runInputGuardrails(
            agent: currentAgent,
            context: runContext,
            input: modelInput,
            trace: &trace
        )

        for _ in 1...config.maxTurns {
            try runContext.throwingIfCancelled()
            trace.items.append(.agentStarted(currentAgent.name))
            config.hooks.onAgentStart(currentAgent)

            let tools = try await enabledTools(for: currentAgent, context: runContext)
            let handoffs = try await enabledHandoffs(for: currentAgent, context: runContext)
            let model = try await resolveModel(for: currentAgent)
            let instructions = try await currentAgent.instructions?.resolve(context: runContext, agent: currentAgent)
            let settings = currentAgent.modelSettings.merging(config.modelSettings)

            config.hooks.onModelStart(currentAgent)
            trace.items.append(.modelRequest(currentAgent.name))
            let response = try await model.getResponse(ModelRequest(
                instructions: instructions,
                input: modelInput,
                context: runContext,
                settings: settings,
                tools: tools.map(\.descriptor),
                handoffs: handoffs.map(\.descriptor),
                outputSchema: currentAgent.outputSchema,
                previousResponseID: config.previousResponseID ?? lastResponseID,
                conversationID: config.conversationID,
                tracing: config.traceIncludeSensitiveData ? .enabled(includeData: true) : .enabled(includeData: false)
            ))
            lastResponseID = response.id
            trace.items.append(.modelResponse(response))
            config.hooks.onModelEnd(response)

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
                if let inputFilter = handoff.inputFilter {
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

        throw AgentsError.maxTurnsExceeded(config.maxTurns)
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
        for processor in config.tracingProcessors {
            await processor.process(trace)
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
        for guardrail in agent.outputGuardrails {
            let result = try await guardrail.run(context: context, agent: agent, output: output)
            config.hooks.onGuardrail(guardrail.name, result)
            if result.tripwireTriggered {
                trace.items.append(.guardrail(guardrail.name))
                throw AgentsError.outputGuardrailTripwire(name: guardrail.name, reason: result.outputInfo)
            }
        }
    }

    private func configInputGuardrails(for agent: Agent<Context>) -> [InputGuardrail<Context>] {
        agent.inputGuardrails
    }

    private func runToolCalls(
        _ calls: [FunctionCall],
        tools: [FunctionTool<Context>],
        context: RunContext<Context>,
        trace: inout Trace
    ) async throws -> [ToolRunResult] {
        var results: [ToolRunResult] = []
        for call in calls {
            guard let tool = tools.first(where: { $0.descriptor.name == call.name }) else {
                throw AgentsError.toolNotFound(call.name)
            }
            let toolContext = ToolContext(runContext: context, call: call)
            trace.items.append(.toolCall(call))
            config.hooks.onToolStart(tool, call)

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

            let callOutput = FunctionCallOutput(callID: call.callID, output: output.modelValue)
            trace.items.append(.toolResult(callOutput))
            config.hooks.onToolEnd(callOutput)
            results.append(ToolRunResult(call: call, output: output))
        }
        return results
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
            return results.first?.output.modelValue.prettyPrinted()
        case .stopAtTools(let names):
            return results.first { names.contains($0.call.name) }?.output.modelValue.prettyPrinted()
        case .custom(let resolver):
            let result = try await resolver(context, results)
            guard result.isFinalOutput else {
                return nil
            }
            return result.finalOutput ?? results.first?.output.modelValue.prettyPrinted() ?? ""
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
