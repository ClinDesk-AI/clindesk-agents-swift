import Foundation

struct PreparedSessionInput: Sendable {
    var modelInput: [ModelInputItem]
    var sessionInputItems: [ModelInputItem]
}

extension RunnerLoop {
    func persistSessionItemsForGuardrailTrip(_ sessionInputItems: [ModelInputItem]) async throws {
        guard let session = config.session else {
            return
        }
        try await session.addItems(sessionInputItems)
    }

    func prepareInitialInput() async throws -> PreparedSessionInput {
        guard let session = config.session else {
            return PreparedSessionInput(modelInput: input, sessionInputItems: input)
        }
        let resolvedSettings = (session.sessionSettings ?? SessionSettings())
            .resolve(config.sessionSettings)
        let history = ItemHelpers.normalizeInputItemsForModel(
            try await session.getItems(limit: resolvedSettings.limit)
        )
        let newInput = ItemHelpers.normalizeInputItemsForModel(input)
        let prepared: [ModelInputItem]
        let sessionInputItems: [ModelInputItem]
        let historyIndexes: Set<Int>
        if let callback = config.sessionInputCallback {
            prepared = try await callback(history, newInput)
            let classification = Self.classifyPreparedSessionItems(
                in: prepared,
                history: history,
                newInput: newInput
            )
            sessionInputItems = classification.sessionInputItems
            historyIndexes = classification.historyIndexes
        } else {
            prepared = history + newInput
            sessionInputItems = newInput
            historyIndexes = Set(0..<history.count)
        }
        let filtered = ItemHelpers.dropOrphanToolCalls(
            ItemHelpers.normalizeInputItemsForModel(prepared),
            pruningIndexes: historyIndexes
        )
        return PreparedSessionInput(
            modelInput: ItemHelpers.deduplicateInputItemsPreferringLatest(filtered),
            sessionInputItems: ItemHelpers.normalizeInputItemsForModel(sessionInputItems)
        )
    }

    static func classifyPreparedSessionItems(
        in prepared: [ModelInputItem],
        history: [ModelInputItem],
        newInput: [ModelInputItem]
    ) -> (historyIndexes: Set<Int>, sessionInputItems: [ModelInputItem]) {
        var historyCounts: [String: Int] = [:]
        for item in history {
            guard let fingerprint = ItemHelpers.fingerprintInputItem(item) else {
                continue
            }
            historyCounts[fingerprint, default: 0] += 1
        }
        var newInputCounts: [String: Int] = [:]
        for item in newInput {
            guard let fingerprint = ItemHelpers.fingerprintInputItem(item) else {
                continue
            }
            newInputCounts[fingerprint, default: 0] += 1
        }

        var historyIndexes = Set<Int>()
        var sessionInputItems: [ModelInputItem] = []
        for (index, item) in prepared.enumerated() {
            guard let fingerprint = ItemHelpers.fingerprintInputItem(item) else {
                sessionInputItems.append(item)
                continue
            }
            if let newInputCount = newInputCounts[fingerprint], newInputCount > 0 {
                newInputCounts[fingerprint] = newInputCount - 1
                sessionInputItems.append(item)
            } else if let historyCount = historyCounts[fingerprint], historyCount > 0 {
                historyCounts[fingerprint] = historyCount - 1
                historyIndexes.insert(index)
            } else {
                sessionInputItems.append(item)
            }
        }
        return (historyIndexes, sessionInputItems)
    }

    func prepareRunLoopStart() async throws -> RunLoopStartResult<Context> {
        var runContext = resumeState?.runContext ?? RunContext(context: contextValue)
        let existingCancellation = runContext.cancellation
        runContext.cancellation = {
            existingCancellation() || Task.isCancelled
        }
        var trace = resumeState?.trace ?? Trace(
            id: config.traceID ?? UUID().uuidString,
            workflowName: config.workflowName,
            groupID: config.groupID,
            metadata: config.traceMetadata,
            includeSensitiveData: config.traceIncludeSensitiveData
        )

        let currentAgent = resumeState?.currentAgent ?? startingAgent
        let resultInput = input
        var sessionInputItems: [ModelInputItem]
        var modelInput: [ModelInputItem]
        if let resumeState {
            modelInput = resumeState.modelInput
            sessionInputItems = resumeState.sessionInputItems
        } else {
            let preparedInput = try await prepareInitialInput()
            modelInput = preparedInput.modelInput
            sessionInputItems = preparedInput.sessionInputItems
        }
        var newItems: [ModelInputItem] = resumeState?.newItems ?? []
        let modelResponses: [ModelResponse] = resumeState?.modelResponses ?? []
        let lastResponseID = resumeState?.lastResponseID
        var toolUseTracker = AgentToolUseTracker<Context>(
            snapshot: resumeState?.toolUseTrackerSnapshot ?? [:]
        )
        let promptCacheKeyResolver = PromptCacheKeyResolver(runState: resumeState)
        let shouldRunAgentStartHooks = resumeState == nil
        var toolInputGuardrailResults: [ToolInputGuardrailResult] = resumeState?.toolInputGuardrailResults ?? []
        var toolOutputGuardrailResults: [ToolOutputGuardrailResult] = resumeState?.toolOutputGuardrailResults ?? []
        var inputGuardrailResults: [InputGuardrailResult] = []

        if resumeState == nil && !config.tracingDisabled {
            for processor in config.tracingProcessors {
                await processor.onTraceStart(trace)
            }
            await (await getTraceProvider()).onTraceStart(trace)
        }

        func state() -> RunLoopState<Context> {
            RunLoopState(
                runContext: runContext,
                trace: trace,
                currentAgent: currentAgent,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: modelInput,
                newItems: newItems,
                modelResponses: modelResponses,
                lastResponseID: lastResponseID,
                toolUseTracker: toolUseTracker,
                shouldRunAgentStartHooks: shouldRunAgentStartHooks,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: toolInputGuardrailResults,
                toolOutputGuardrailResults: toolOutputGuardrailResults,
                promptCacheKeyResolver: promptCacheKeyResolver,
                turn: resumeState?.currentTurn ?? 0
            )
        }

        if let resumeState {
            inputGuardrailResults = resumeState.inputGuardrailResults
            if !resumeState.pendingFunctionCalls.isEmpty {
                let functionTools = try await enabledTools(for: currentAgent, context: runContext)
                    .compactMap(\.functionTool)
                let functionToolLookupMap = try ToolIdentity.buildFunctionToolLookupMap(functionTools)
                let resumed = try await runToolCalls(
                    resumeState.pendingFunctionCalls,
                    tools: functionTools,
                    toolsByLookupKey: functionToolLookupMap,
                    agent: currentAgent,
                    context: runContext,
                    trace: &trace
                )
                switch resumed {
                case .interrupted(let interruptions):
                    let result = interruptedResult(
                        interruptions: interruptions,
                        pendingFunctionCalls: resumeState.pendingFunctionCalls,
                        pendingCustomToolCalls: resumeState.pendingCustomToolCalls,
                        pendingShellCalls: resumeState.pendingShellCalls,
                        pendingApplyPatchCalls: resumeState.pendingApplyPatchCalls,
                        agent: currentAgent,
                        context: runContext,
                        trace: trace,
                        resultInput: resultInput,
                        sessionInputItems: sessionInputItems,
                        modelInput: modelInput,
                        newItems: newItems,
                        modelResponses: modelResponses,
                        responseID: lastResponseID,
                        turn: resumeState.currentTurn,
                        inputGuardrailResults: inputGuardrailResults,
                        toolInputGuardrailResults: toolInputGuardrailResults,
                        toolOutputGuardrailResults: toolOutputGuardrailResults,
                        toolUseTracker: toolUseTracker,
                        promptCacheKeyResolver: promptCacheKeyResolver
                    )
                    return RunLoopStartResult(state: state(), completedResult: result)
                case .completed(let results):
                    toolInputGuardrailResults.append(contentsOf: results.flatMap(\.inputGuardrailResults))
                    toolOutputGuardrailResults.append(contentsOf: results.flatMap(\.outputGuardrailResults))
                    toolUseTracker.recordFunctionToolResults(results, agent: currentAgent)
                    let outputs = results.map {
                        ItemHelpers.toolCallOutputItem(toolCall: $0.call, output: $0.output)
                    }
                    let outputItems = outputs.map(ModelInputItem.functionCallOutput)
                    modelInput.append(contentsOf: outputItems)
                    newItems.append(contentsOf: outputItems)
                    for output in outputs {
                        await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                            agent: currentAgent,
                            output: output
                        ))
                    }
                    if !results.isEmpty {
                        let toolUseResolution = try await resolveToolUseBehavior(
                            currentAgent.toolUseBehavior,
                            context: runContext,
                            results: results
                        )
                        if toolUseResolution.isFinalOutput {
                            let result = try await finish(
                                toolUseResolution.finalOutput,
                                agent: currentAgent,
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
                            return RunLoopStartResult(state: state(), completedResult: result)
                        }
                    }
                }
            }
            if !resumeState.pendingCustomToolCalls.isEmpty {
                let customTools = try await enabledTools(for: currentAgent, context: runContext)
                    .compactMap(\.customTool)
                let resumed = try await runCustomToolCalls(
                    resumeState.pendingCustomToolCalls,
                    tools: customTools,
                    agent: currentAgent,
                    context: &runContext,
                    trace: &trace
                )
                switch resumed {
                case .interrupted(let interruptions):
                    let result = interruptedResult(
                        interruptions: interruptions,
                        pendingFunctionCalls: [],
                        pendingCustomToolCalls: resumeState.pendingCustomToolCalls,
                        pendingShellCalls: resumeState.pendingShellCalls,
                        pendingApplyPatchCalls: resumeState.pendingApplyPatchCalls,
                        agent: currentAgent,
                        context: runContext,
                        trace: trace,
                        resultInput: resultInput,
                        sessionInputItems: sessionInputItems,
                        modelInput: modelInput,
                        newItems: newItems,
                        modelResponses: modelResponses,
                        responseID: lastResponseID,
                        turn: resumeState.currentTurn,
                        inputGuardrailResults: inputGuardrailResults,
                        toolInputGuardrailResults: toolInputGuardrailResults,
                        toolOutputGuardrailResults: toolOutputGuardrailResults,
                        toolUseTracker: toolUseTracker,
                        promptCacheKeyResolver: promptCacheKeyResolver
                    )
                    return RunLoopStartResult(state: state(), completedResult: result)
                case .completed(let customResults):
                    toolUseTracker.recordCustomToolResults(customResults, agent: currentAgent)
                    let customOutputItems = customResults.map { result in
                        ModelInputItem.customToolCallOutput(CustomToolCallOutput(
                            callID: result.call.callID,
                            output: result.output
                        ))
                    }
                    modelInput.append(contentsOf: customOutputItems)
                    newItems.append(contentsOf: customOutputItems)
                    for outputItem in customOutputItems {
                        await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                            for: outputItem,
                            agent: currentAgent
                        ))
                    }
                }
            }
            if !resumeState.pendingShellCalls.isEmpty {
                let shellTools = try await enabledTools(for: currentAgent, context: runContext)
                    .compactMap(\.shellTool)
                let resumed = try await runShellCalls(
                    resumeState.pendingShellCalls,
                    tools: shellTools,
                    agent: currentAgent,
                    context: &runContext,
                    trace: &trace
                )
                switch resumed {
                case .interrupted(let interruptions):
                    let result = interruptedResult(
                        interruptions: interruptions,
                        pendingFunctionCalls: [],
                        pendingCustomToolCalls: [],
                        pendingShellCalls: resumeState.pendingShellCalls,
                        pendingApplyPatchCalls: resumeState.pendingApplyPatchCalls,
                        agent: currentAgent,
                        context: runContext,
                        trace: trace,
                        resultInput: resultInput,
                        sessionInputItems: sessionInputItems,
                        modelInput: modelInput,
                        newItems: newItems,
                        modelResponses: modelResponses,
                        responseID: lastResponseID,
                        turn: resumeState.currentTurn,
                        inputGuardrailResults: inputGuardrailResults,
                        toolInputGuardrailResults: toolInputGuardrailResults,
                        toolOutputGuardrailResults: toolOutputGuardrailResults,
                        toolUseTracker: toolUseTracker,
                        promptCacheKeyResolver: promptCacheKeyResolver
                    )
                    return RunLoopStartResult(state: state(), completedResult: result)
                case .completed(let shellResults):
                    let shellOutputItems = shellResults.map { result in
                        ModelInputItem.shellCallOutput(ShellCallOutput(
                            callID: result.call.callID,
                            output: result.output,
                            status: result.status
                        ))
                    }
                    modelInput.append(contentsOf: shellOutputItems)
                    newItems.append(contentsOf: shellOutputItems)
                    for outputItem in shellOutputItems {
                        await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                            for: outputItem,
                            agent: currentAgent
                        ))
                    }
                }
            }
            if !resumeState.pendingApplyPatchCalls.isEmpty {
                let applyPatchTools = try await enabledTools(for: currentAgent, context: runContext)
                    .compactMap(\.applyPatchTool)
                let resumed = try await runApplyPatchCalls(
                    resumeState.pendingApplyPatchCalls,
                    tools: applyPatchTools,
                    agent: currentAgent,
                    context: &runContext,
                    trace: &trace
                )
                switch resumed {
                case .interrupted(let interruptions):
                    let result = interruptedResult(
                        interruptions: interruptions,
                        pendingFunctionCalls: [],
                        pendingCustomToolCalls: [],
                        pendingShellCalls: [],
                        pendingApplyPatchCalls: resumeState.pendingApplyPatchCalls,
                        agent: currentAgent,
                        context: runContext,
                        trace: trace,
                        resultInput: resultInput,
                        sessionInputItems: sessionInputItems,
                        modelInput: modelInput,
                        newItems: newItems,
                        modelResponses: modelResponses,
                        responseID: lastResponseID,
                        turn: resumeState.currentTurn,
                        inputGuardrailResults: inputGuardrailResults,
                        toolInputGuardrailResults: toolInputGuardrailResults,
                        toolOutputGuardrailResults: toolOutputGuardrailResults,
                        toolUseTracker: toolUseTracker,
                        promptCacheKeyResolver: promptCacheKeyResolver
                    )
                    return RunLoopStartResult(state: state(), completedResult: result)
                case .completed(let applyPatchResults):
                    let applyPatchOutputItems = applyPatchResults.map { result in
                        ModelInputItem.applyPatchCallOutput(ApplyPatchCallOutput(
                            callID: result.call.callID,
                            status: result.status,
                            output: result.output
                        ))
                    }
                    modelInput.append(contentsOf: applyPatchOutputItems)
                    newItems.append(contentsOf: applyPatchOutputItems)
                    for outputItem in applyPatchOutputItems {
                        await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                            for: outputItem,
                            agent: currentAgent
                        ))
                    }
                }
            }
        } else {
            do {
                inputGuardrailResults = try await runInputGuardrails(
                    agent: currentAgent,
                    context: runContext,
                    input: resultInput,
                    trace: &trace
                )
            } catch {
                try await persistSessionItemsForGuardrailTrip(sessionInputItems)
                throw error
            }
        }

        return RunLoopStartResult(state: state(), completedResult: nil)
    }
}
