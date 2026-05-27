import Foundation

struct RunnerLoop<Context: Sendable> {
    let startingAgent: Agent<Context>
    let input: [ModelInputItem]
    let contextValue: Context?
    let modelProvider: (any ModelProvider)?
    let config: RunConfig<Context>
    let resumeState: RunState<Context>?

    init(
        startingAgent: Agent<Context>,
        input: [ModelInputItem],
        contextValue: Context?,
        modelProvider: (any ModelProvider)?,
        config: RunConfig<Context>
    ) {
        self.startingAgent = startingAgent
        self.input = input
        self.contextValue = contextValue
        self.modelProvider = modelProvider
        self.config = config
        self.resumeState = nil
    }

    init(resumeState: RunState<Context>) {
        self.startingAgent = resumeState.startingAgent
        self.input = resumeState.originalInput
        self.contextValue = resumeState.runContext.context
        self.modelProvider = resumeState.modelProvider
        self.config = resumeState.config
        self.resumeState = resumeState
    }

    func run() async throws -> RunResult {
        try validateConfig()

        let start = try await prepareRunLoopStart()
        if let completedResult = start.completedResult {
            return completedResult
        }

        var runContext = start.state.runContext
        var trace = start.state.trace
        var currentAgent = start.state.currentAgent
        var resultInput = start.state.resultInput
        let sessionInputItems = start.state.sessionInputItems
        var modelInput = start.state.modelInput
        var newItems = start.state.newItems
        var modelResponses = start.state.modelResponses
        var lastResponseID = start.state.lastResponseID
        var toolUseTracker = start.state.toolUseTracker
        var promptCacheKeyResolver = start.state.promptCacheKeyResolver
        var shouldRunAgentStartHooks = start.state.shouldRunAgentStartHooks
        let inputGuardrailResults = start.state.inputGuardrailResults
        var toolInputGuardrailResults = start.state.toolInputGuardrailResults
        var toolOutputGuardrailResults = start.state.toolOutputGuardrailResults
        var turn = start.state.turn

        var taskSpan = await makeTaskSpan(trace: trace)
        let taskUsageStart = runContext.usage
        await startRunSpan(&taskSpan)
        var currentAgentSpan: Span?

        func ensureAgentSpan(
            tools: [Tool<Context>],
            handoffs: [Handoff<Context>]
        ) async {
            guard currentAgentSpan == nil else {
                return
            }
            var span = await makeAgentSpan(
                agent: currentAgent,
                tools: tools,
                handoffs: handoffs,
                parent: taskSpan
            )
            await startRunSpan(&span)
            currentAgentSpan = span
        }

        func finishCurrentAgentSpan(error: Error? = nil) async {
            guard var span = currentAgentSpan else {
                return
            }
            await finishRunSpan(&span, error: error)
            currentAgentSpan = nil
        }

        func finishTaskSpan(error: Error? = nil) async {
            attachUsageDelta(to: &taskSpan, from: taskUsageStart, to: runContext.usage)
            await finishRunSpan(&taskSpan, error: error)
        }

        func finishActiveSpans(error: Error? = nil) async {
            await finishCurrentAgentSpan(error: error)
            await finishTaskSpan(error: error)
        }

        do {
            while config.maxTurns == nil || turn < (config.maxTurns ?? 0) {
            turn += 1
            try runContext.throwingIfCancelled()
            let publicAgent = currentAgent.publicAgent
            if shouldRunAgentStartHooks {
                trace.items.append(.agentStarted(publicAgent.name))
                await emitStreamEvent(RunnerStreaming.agentUpdated(publicAgent))
                try await callAgentStartHooks(context: runContext, agent: currentAgent)
                shouldRunAgentStartHooks = false
            }

            let tools = try await enabledTools(for: currentAgent, context: runContext)
            let functionTools = tools.compactMap(\.functionTool)
            let functionToolLookupMap = try ToolIdentity.buildFunctionToolLookupMap(functionTools)
            let customTools = tools.compactMap(\.customTool)
            let computerTools = tools.compactMap(\.computerTool)
            let localShellTools = tools.compactMap(\.localShellTool)
            let shellTools = tools.compactMap(\.shellTool)
            let applyPatchTools = tools.compactMap(\.applyPatchTool)
            let handoffs = try await enabledHandoffs(for: currentAgent, context: runContext)
            await ensureAgentSpan(tools: tools, handoffs: handoffs)
            var turnSpan = await makeTurnSpan(
                turn: turn,
                agent: currentAgent,
                parent: currentAgentSpan ?? taskSpan
            )
            let turnUsageStart = runContext.usage
            await startRunSpan(&turnSpan)

            do {
                let modelResponse = try await getNewResponse(
                    agent: currentAgent,
                    runContext: runContext,
                    modelInput: modelInput,
                    tools: tools,
                    handoffs: handoffs,
                    toolUseTracker: toolUseTracker,
                    promptCacheKeyResolver: &promptCacheKeyResolver,
                    trace: &trace
                )
                let response = modelResponse.response
                runContext = modelResponse.runContext
                lastResponseID = response.responseID
                modelResponses.append(response)

            let processedResponse = await processModelResponse(
                response,
                agent: currentAgent,
                modelInput: modelInput,
                newItems: newItems,
                handoffs: handoffs,
                functionToolLookupMap: functionToolLookupMap,
                customTools: customTools,
                computerTools: computerTools,
                localShellTools: localShellTools,
                shellTools: shellTools,
                applyPatchTools: applyPatchTools
            )
            modelInput = processedResponse.modelInput
            newItems = processedResponse.newItems

            if let handoffCall = processedResponse.handoffCalls.first {
                let resolution = try await executeHandoff(
                    handoffCall: handoffCall,
                    handoffCalls: processedResponse.handoffCalls,
                    handoffs: handoffs,
                    currentAgent: currentAgent,
                    runContext: runContext,
                    trace: &trace,
                    resultInput: resultInput,
                    modelInput: modelInput,
                    newItems: newItems,
                    inputHistory: processedResponse.inputHistory,
                    preHandoffItems: processedResponse.preHandoffItems,
                    outputInputItems: processedResponse.outputInputItems,
                    parentSpan: turnSpan
                )
                currentAgent = resolution.agent
                resultInput = resolution.resultInput
                modelInput = resolution.modelInput
                newItems = resolution.newItems
                shouldRunAgentStartHooks = resolution.shouldRunAgentStartHooks
                attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                await finishRunSpan(&turnSpan)
                await finishCurrentAgentSpan()
                continue
            }

            if let unknown = processedResponse.unknownFunctionCalls.first {
                switch config.toolNotFoundBehavior {
                case .raiseError:
                    throw AgentsError.toolNotFound(unknown.name)
                case .returnErrorToModel:
                    let message = await resolveToolNotFoundMessage(
                        toolName: unknown.name,
                        callID: unknown.callID,
                        context: runContext
                    )
                    let output = FunctionCallOutput(
                        callID: unknown.callID,
                        output: .string(message)
                    )
                    modelInput.append(.functionCallOutput(output))
                    newItems.append(.functionCallOutput(output))
                    trace.items.append(.toolResult(output))
                    await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                        agent: publicAgent,
                        output: output
                    ))
                    attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                    await finishRunSpan(&turnSpan)
                    continue
                }
            }

            let toolCalls = processedResponse.toolCalls
            let customToolCalls = processedResponse.customToolCalls
            let computerCalls = processedResponse.computerCalls
            let localShellCalls = processedResponse.localShellCalls
            let shellCalls = processedResponse.shellCalls
            let applyPatchCalls = processedResponse.applyPatchCalls
            if let unknown = processedResponse.unknownCustomToolCalls.first {
                throw AgentsError.toolNotFound(unknown.name)
            }
            if !processedResponse.unknownComputerCalls.isEmpty {
                throw AgentsError.toolNotFound("computer")
            }
            if !processedResponse.unknownLocalShellCalls.isEmpty {
                throw AgentsError.toolNotFound("local_shell")
            }
            if !processedResponse.unknownShellCalls.isEmpty {
                throw AgentsError.toolNotFound("shell")
            }
            if !processedResponse.unknownApplyPatchCalls.isEmpty {
                throw AgentsError.toolNotFound("apply_patch")
            }

            if !toolCalls.isEmpty
                || !customToolCalls.isEmpty
                || !computerCalls.isEmpty
                || !localShellCalls.isEmpty
                || !shellCalls.isEmpty
                || !applyPatchCalls.isEmpty
            {
                let toolSideEffects = try await executeToolCallsAndSideEffects(
                    toolCalls: toolCalls,
                    customToolCalls: customToolCalls,
                    computerCalls: computerCalls,
                    localShellCalls: localShellCalls,
                    shellCalls: shellCalls,
                    applyPatchCalls: applyPatchCalls,
                    functionTools: functionTools,
                    functionToolLookupMap: functionToolLookupMap,
                    customTools: customTools,
                    computerTools: computerTools,
                    localShellTools: localShellTools,
                    shellTools: shellTools,
                    applyPatchTools: applyPatchTools,
                    agent: currentAgent,
                    runContext: runContext,
                    trace: &trace,
                    resultInput: resultInput,
                    sessionInputItems: sessionInputItems,
                    modelInput: modelInput,
                    newItems: newItems,
                    modelResponses: modelResponses,
                    responseID: lastResponseID,
                    turn: turn,
                    inputGuardrailResults: inputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults,
                    toolUseTracker: toolUseTracker,
                    promptCacheKeyResolver: promptCacheKeyResolver,
                    parentSpan: turnSpan
                )
                switch toolSideEffects {
                case .completed(let result):
                    attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                    await finishRunSpan(&turnSpan)
                    await finishActiveSpans()
                    return result
                case .runAgain(let state):
                    runContext = state.runContext
                    modelInput = state.modelInput
                    newItems = state.newItems
                    toolUseTracker = state.toolUseTracker
                    toolInputGuardrailResults = state.toolInputGuardrailResults
                    toolOutputGuardrailResults = state.toolOutputGuardrailResults
                    attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                    await finishRunSpan(&turnSpan)
                    continue
                }
            }

            if let refusal = response.refusal {
                let result = try await handleModelRefusal(
                    refusal,
                    agent: publicAgent,
                    context: runContext,
                    trace: &trace,
                    resultInput: resultInput,
                    sessionInputItems: sessionInputItems,
                    modelInput: modelInput,
                    newItems: newItems,
                    modelResponses: modelResponses,
                    responseID: lastResponseID,
                    inputGuardrailResults: inputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults
                )
                attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                await finishRunSpan(&turnSpan)
                await finishActiveSpans()
                return result
            }

            let finalOutput = response.outputText
            let result = try await finish(
                finalOutput,
                agent: publicAgent,
                context: runContext,
                trace: &trace,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: modelInput,
                newItems: newItems,
                modelResponses: modelResponses,
                responseID: lastResponseID,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: toolInputGuardrailResults,
                toolOutputGuardrailResults: toolOutputGuardrailResults
            )
            attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
            await finishRunSpan(&turnSpan)
            await finishActiveSpans()
            return result
            } catch {
                attachUsageDelta(to: &turnSpan, from: turnUsageStart, to: runContext.usage)
                await finishRunSpan(&turnSpan, error: error)
                throw error
            }
        }

        let result = try await handleMaxTurnsExceeded(
            maxTurns: config.maxTurns ?? turn,
            agent: currentAgent.publicAgent,
            context: runContext,
            trace: &trace,
            resultInput: resultInput,
            sessionInputItems: sessionInputItems,
            modelInput: modelInput,
            newItems: newItems,
            modelResponses: modelResponses,
            responseID: lastResponseID,
            inputGuardrailResults: inputGuardrailResults,
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults
        )
            await finishActiveSpans(error: AgentsError.maxTurnsExceeded(config.maxTurns ?? turn))
            return result
        } catch {
            await finishActiveSpans(error: error)
            throw error
        }
    }

}
