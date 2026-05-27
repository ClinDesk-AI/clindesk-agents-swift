extension RunnerLoop {
    func executeToolCallsAndSideEffects(
        toolCalls: [FunctionCall],
        customToolCalls: [CustomToolCall],
        computerCalls: [ComputerCall],
        localShellCalls: [LocalShellCall],
        shellCalls: [ShellCall],
        applyPatchCalls: [ApplyPatchCall],
        functionTools: [FunctionTool<Context>],
        functionToolLookupMap: [FunctionToolLookupKey: FunctionTool<Context>],
        customTools: [CustomTool<Context>],
        computerTools: [ComputerTool<Context>],
        localShellTools: [LocalShellTool<Context>],
        shellTools: [ShellTool<Context>],
        applyPatchTools: [ApplyPatchTool<Context>],
        agent: Agent<Context>,
        runContext: RunContext<Context>,
        trace: inout Trace,
        resultInput: [ModelInputItem],
        sessionInputItems: [ModelInputItem],
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        responseID: String?,
        turn: Int,
        inputGuardrailResults: [InputGuardrailResult],
        toolInputGuardrailResults: [ToolInputGuardrailResult],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult],
        toolUseTracker: AgentToolUseTracker<Context>,
        promptCacheKeyResolver: PromptCacheKeyResolver<Context>,
        parentSpan: Span
    ) async throws -> ToolSideEffectOutcome<Context> {
        var resolvedRunContext = runContext
        var resolvedModelInput = modelInput
        var resolvedNewItems = newItems
        var resolvedToolUseTracker = toolUseTracker
        var resolvedToolInputGuardrailResults = toolInputGuardrailResults
        var resolvedToolOutputGuardrailResults = toolOutputGuardrailResults

        let toolOutcome = try await runToolCalls(
            toolCalls,
            tools: functionTools,
            toolsByLookupKey: functionToolLookupMap,
            agent: agent,
            context: resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let results: [ToolRunResult]
        switch toolOutcome {
        case .completed(let completedResults):
            results = completedResults
        case .interrupted(let interruptions):
            return .completed(interruptedResult(
                interruptions: interruptions,
                pendingFunctionCalls: toolCalls,
                pendingCustomToolCalls: customToolCalls,
                pendingShellCalls: shellCalls,
                pendingApplyPatchCalls: applyPatchCalls,
                agent: agent,
                context: resolvedRunContext,
                trace: trace,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: resolvedModelInput,
                newItems: resolvedNewItems,
                modelResponses: modelResponses,
                responseID: responseID,
                turn: turn,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: resolvedToolInputGuardrailResults,
                toolOutputGuardrailResults: resolvedToolOutputGuardrailResults,
                toolUseTracker: resolvedToolUseTracker,
                promptCacheKeyResolver: promptCacheKeyResolver
            ))
        }

        resolvedToolInputGuardrailResults.append(contentsOf: results.flatMap(\.inputGuardrailResults))
        resolvedToolOutputGuardrailResults.append(contentsOf: results.flatMap(\.outputGuardrailResults))

        let customOutcome = try await runCustomToolCalls(
            customToolCalls,
            tools: customTools,
            agent: agent,
            context: &resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let customResults: [CustomToolRunResult]
        switch customOutcome {
        case .completed(let completedResults):
            customResults = completedResults
        case .interrupted(let interruptions):
            let outputs = results.map {
                ItemHelpers.toolCallOutputItem(toolCall: $0.call, output: $0.output)
            }
            let outputItems = outputs.map(ModelInputItem.functionCallOutput)
            resolvedModelInput.append(contentsOf: outputItems)
            resolvedNewItems.append(contentsOf: outputItems)
            for output in outputs {
                await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                    agent: agent,
                    output: output
                ))
            }
            return .completed(interruptedResult(
                interruptions: interruptions,
                pendingFunctionCalls: [],
                pendingCustomToolCalls: customToolCalls,
                pendingShellCalls: shellCalls,
                pendingApplyPatchCalls: applyPatchCalls,
                agent: agent,
                context: resolvedRunContext,
                trace: trace,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: resolvedModelInput,
                newItems: resolvedNewItems,
                modelResponses: modelResponses,
                responseID: responseID,
                turn: turn,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: resolvedToolInputGuardrailResults,
                toolOutputGuardrailResults: resolvedToolOutputGuardrailResults,
                toolUseTracker: resolvedToolUseTracker,
                promptCacheKeyResolver: promptCacheKeyResolver
            ))
        }

        let computerOutcome = try await runComputerCalls(
            computerCalls,
            tools: computerTools,
            agent: agent,
            context: resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let computerResults: [ComputerRunResult]
        switch computerOutcome {
        case .completed(let completedResults):
            computerResults = completedResults
        }

        let localShellOutcome = try await runLocalShellCalls(
            localShellCalls,
            tools: localShellTools,
            agent: agent,
            context: resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let localShellResults: [LocalShellRunResult]
        switch localShellOutcome {
        case .completed(let completedResults):
            localShellResults = completedResults
        }

        let shellOutcome = try await runShellCalls(
            shellCalls,
            tools: shellTools,
            agent: agent,
            context: &resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let shellResults: [ShellRunResult]
        switch shellOutcome {
        case .completed(let completedResults):
            shellResults = completedResults
        case .interrupted(let interruptions):
            let outputs = results.map {
                ItemHelpers.toolCallOutputItem(toolCall: $0.call, output: $0.output)
            }
            let outputItems = outputs.map(ModelInputItem.functionCallOutput)
            resolvedModelInput.append(contentsOf: outputItems)
            resolvedNewItems.append(contentsOf: outputItems)
            for output in outputs {
                await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                    agent: agent,
                    output: output
                ))
            }

            let customOutputItems = customResults.map { result in
                ModelInputItem.customToolCallOutput(CustomToolCallOutput(
                    callID: result.call.callID,
                    output: result.output
                ))
            }
            resolvedModelInput.append(contentsOf: customOutputItems)
            resolvedNewItems.append(contentsOf: customOutputItems)
            for outputItem in customOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            let computerOutputItems = computerResults.map { result in
                ModelInputItem.computerCallOutput(ComputerCallOutput(
                    callID: result.call.callID,
                    output: [
                        "type": "computer_screenshot",
                        "image_url": .string(result.imageURL)
                    ],
                    acknowledgedSafetyChecks: result.acknowledgedSafetyChecks
                ))
            }
            resolvedModelInput.append(contentsOf: computerOutputItems)
            resolvedNewItems.append(contentsOf: computerOutputItems)
            for outputItem in computerOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            let localShellOutputItems = localShellResults.map { result in
                ModelInputItem.localShellCallOutput(LocalShellCallOutput(
                    callID: result.call.callID,
                    output: result.output
                ))
            }
            resolvedModelInput.append(contentsOf: localShellOutputItems)
            resolvedNewItems.append(contentsOf: localShellOutputItems)
            for outputItem in localShellOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            return .completed(interruptedResult(
                interruptions: interruptions,
                pendingFunctionCalls: [],
                pendingCustomToolCalls: [],
                pendingShellCalls: shellCalls,
                pendingApplyPatchCalls: applyPatchCalls,
                agent: agent,
                context: resolvedRunContext,
                trace: trace,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: resolvedModelInput,
                newItems: resolvedNewItems,
                modelResponses: modelResponses,
                responseID: responseID,
                turn: turn,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: resolvedToolInputGuardrailResults,
                toolOutputGuardrailResults: resolvedToolOutputGuardrailResults,
                toolUseTracker: resolvedToolUseTracker,
                promptCacheKeyResolver: promptCacheKeyResolver
            ))
        }

        let applyPatchOutcome = try await runApplyPatchCalls(
            applyPatchCalls,
            tools: applyPatchTools,
            agent: agent,
            context: &resolvedRunContext,
            trace: &trace,
            parentSpan: parentSpan
        )
        let applyPatchResults: [ApplyPatchRunResult]
        switch applyPatchOutcome {
        case .completed(let completedResults):
            applyPatchResults = completedResults
        case .interrupted(let interruptions):
            let outputs = results.map {
                ItemHelpers.toolCallOutputItem(toolCall: $0.call, output: $0.output)
            }
            let outputItems = outputs.map(ModelInputItem.functionCallOutput)
            resolvedModelInput.append(contentsOf: outputItems)
            resolvedNewItems.append(contentsOf: outputItems)
            for output in outputs {
                await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                    agent: agent,
                    output: output
                ))
            }

            let customOutputItems = customResults.map { result in
                ModelInputItem.customToolCallOutput(CustomToolCallOutput(
                    callID: result.call.callID,
                    output: result.output
                ))
            }
            resolvedModelInput.append(contentsOf: customOutputItems)
            resolvedNewItems.append(contentsOf: customOutputItems)
            for outputItem in customOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            let computerOutputItems = computerResults.map { result in
                ModelInputItem.computerCallOutput(ComputerCallOutput(
                    callID: result.call.callID,
                    output: [
                        "type": "computer_screenshot",
                        "image_url": .string(result.imageURL)
                    ],
                    acknowledgedSafetyChecks: result.acknowledgedSafetyChecks
                ))
            }
            resolvedModelInput.append(contentsOf: computerOutputItems)
            resolvedNewItems.append(contentsOf: computerOutputItems)
            for outputItem in computerOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            let localShellOutputItems = localShellResults.map { result in
                ModelInputItem.localShellCallOutput(LocalShellCallOutput(
                    callID: result.call.callID,
                    output: result.output
                ))
            }
            resolvedModelInput.append(contentsOf: localShellOutputItems)
            resolvedNewItems.append(contentsOf: localShellOutputItems)
            for outputItem in localShellOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            let shellOutputItems = shellResults.map { result in
                ModelInputItem.shellCallOutput(ShellCallOutput(
                    callID: result.call.callID,
                    output: result.output,
                    status: result.status
                ))
            }
            resolvedModelInput.append(contentsOf: shellOutputItems)
            resolvedNewItems.append(contentsOf: shellOutputItems)
            for outputItem in shellOutputItems {
                await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                    for: outputItem,
                    agent: agent
                ))
            }

            return .completed(interruptedResult(
                interruptions: interruptions,
                pendingFunctionCalls: [],
                pendingCustomToolCalls: [],
                pendingShellCalls: [],
                pendingApplyPatchCalls: applyPatchCalls,
                agent: agent,
                context: resolvedRunContext,
                trace: trace,
                resultInput: resultInput,
                sessionInputItems: sessionInputItems,
                modelInput: resolvedModelInput,
                newItems: resolvedNewItems,
                modelResponses: modelResponses,
                responseID: responseID,
                turn: turn,
                inputGuardrailResults: inputGuardrailResults,
                toolInputGuardrailResults: resolvedToolInputGuardrailResults,
                toolOutputGuardrailResults: resolvedToolOutputGuardrailResults,
                toolUseTracker: resolvedToolUseTracker,
                promptCacheKeyResolver: promptCacheKeyResolver
            ))
        }

        resolvedToolUseTracker.recordFunctionToolResults(results, agent: agent)
        resolvedToolUseTracker.recordCustomToolResults(customResults, agent: agent)

        let outputs = results.map {
            ItemHelpers.toolCallOutputItem(toolCall: $0.call, output: $0.output)
        }
        let outputItems = outputs.map(ModelInputItem.functionCallOutput)
        resolvedModelInput.append(contentsOf: outputItems)
        resolvedNewItems.append(contentsOf: outputItems)
        for output in outputs {
            await emitRunItemStreamEvent(RunnerStreaming.toolOutputEvent(
                agent: agent,
                output: output
            ))
        }

        let customOutputItems = customResults.map { result in
            ModelInputItem.customToolCallOutput(CustomToolCallOutput(
                callID: result.call.callID,
                output: result.output
            ))
        }
        resolvedModelInput.append(contentsOf: customOutputItems)
        resolvedNewItems.append(contentsOf: customOutputItems)
        for outputItem in customOutputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent
            ))
        }

        let computerOutputItems = computerResults.map { result in
            ModelInputItem.computerCallOutput(ComputerCallOutput(
                callID: result.call.callID,
                output: [
                    "type": "computer_screenshot",
                    "image_url": .string(result.imageURL)
                ],
                acknowledgedSafetyChecks: result.acknowledgedSafetyChecks
            ))
        }
        resolvedModelInput.append(contentsOf: computerOutputItems)
        resolvedNewItems.append(contentsOf: computerOutputItems)
        for outputItem in computerOutputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent
            ))
        }

        let localShellOutputItems = localShellResults.map { result in
            ModelInputItem.localShellCallOutput(LocalShellCallOutput(
                callID: result.call.callID,
                output: result.output
            ))
        }
        resolvedModelInput.append(contentsOf: localShellOutputItems)
        resolvedNewItems.append(contentsOf: localShellOutputItems)
        for outputItem in localShellOutputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent
            ))
        }

        let shellOutputItems = shellResults.map { result in
            ModelInputItem.shellCallOutput(ShellCallOutput(
                callID: result.call.callID,
                output: result.output,
                status: result.status
            ))
        }
        resolvedModelInput.append(contentsOf: shellOutputItems)
        resolvedNewItems.append(contentsOf: shellOutputItems)
        for outputItem in shellOutputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent
            ))
        }

        let applyPatchOutputItems = applyPatchResults.map { result in
            ModelInputItem.applyPatchCallOutput(ApplyPatchCallOutput(
                callID: result.call.callID,
                status: result.status,
                output: result.output
            ))
        }
        resolvedModelInput.append(contentsOf: applyPatchOutputItems)
        resolvedNewItems.append(contentsOf: applyPatchOutputItems)
        for outputItem in applyPatchOutputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent
            ))
        }

        if !results.isEmpty {
            let toolUseResolution = try await resolveToolUseBehavior(
                agent.toolUseBehavior,
                context: resolvedRunContext,
                results: results
            )
            if toolUseResolution.isFinalOutput {
                return .completed(try await finish(
                    toolUseResolution.finalOutput,
                    agent: agent,
                    context: resolvedRunContext,
                    trace: &trace,
                    resultInput: resultInput,
                    sessionInputItems: sessionInputItems,
                    modelInput: resolvedModelInput,
                    newItems: resolvedNewItems,
                    modelResponses: modelResponses,
                    responseID: responseID,
                    inputGuardrailResults: inputGuardrailResults,
                    toolInputGuardrailResults: resolvedToolInputGuardrailResults,
                    toolOutputGuardrailResults: resolvedToolOutputGuardrailResults
                ))
            }
        }

        return .runAgain(ToolSideEffectState(
            runContext: resolvedRunContext,
            modelInput: resolvedModelInput,
            newItems: resolvedNewItems,
            toolUseTracker: resolvedToolUseTracker,
            toolInputGuardrailResults: resolvedToolInputGuardrailResults,
            toolOutputGuardrailResults: resolvedToolOutputGuardrailResults
        ))
    }
}
