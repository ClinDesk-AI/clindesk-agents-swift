import Foundation

extension RunnerLoop {
    static func replayItems(
        modelInput: [ModelInputItem],
        resultInput: [ModelInputItem]
    ) -> [ModelInputItem] {
        guard !resultInput.isEmpty, modelInput.count >= resultInput.count else {
            return modelInput
        }
        let maxStart = modelInput.count - resultInput.count
        for start in stride(from: maxStart, through: 0, by: -1) {
            let end = start + resultInput.count
            if Array(modelInput[start..<end]) == resultInput {
                return Array(modelInput.dropFirst(end))
            }
        }
        return modelInput
    }

    func finish(
        _ output: String,
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        resultInput: [ModelInputItem],
        sessionInputItems: [ModelInputItem],
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        responseID: String?,
        inputGuardrailResults: [InputGuardrailResult],
        toolInputGuardrailResults: [ToolInputGuardrailResult],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    ) async throws -> RunResult {
        let publicAgent = agent.publicAgent
        let outputGuardrailResults = try await runOutputGuardrails(
            agent: publicAgent,
            context: context,
            output: output,
            trace: &trace
        )
        trace.items.append(.finalOutput(output))
        trace.endedAt = Date()
        try await callAgentEndHooks(context: context, agent: publicAgent, output: output)
        if let session = config.session {
            try await session.addItems(sessionInputItems + newItems)
        }
        if !config.tracingDisabled {
            for processor in config.tracingProcessors {
                await processor.onTraceEnd(trace)
            }
            await (await getTraceProvider()).onTraceEnd(trace)
        }
        let replayItems = Self.replayItems(modelInput: modelInput, resultInput: resultInput)
        return RunResult(
            input: resultInput,
            finalOutput: output,
            lastAgentName: publicAgent.name,
            lastAgent: AgentSnapshot(publicAgent),
            trace: trace,
            newItems: newItems,
            modelResponses: modelResponses,
            usage: context.usage,
            responseID: responseID,
            inputGuardrailResults: inputGuardrailResults,
            outputGuardrailResults: outputGuardrailResults,
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults,
            modelInputItems: replayItems,
            replayFromModelInputItems: replayItems != newItems
        )
    }

    func interruptedResult(
        interruptions: [ToolApprovalItem],
        pendingFunctionCalls: [FunctionCall],
        pendingCustomToolCalls: [CustomToolCall] = [],
        pendingShellCalls: [ShellCall] = [],
        pendingApplyPatchCalls: [ApplyPatchCall] = [],
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: Trace,
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
        promptCacheKeyResolver: PromptCacheKeyResolver<Context>? = nil
    ) -> RunResult {
        let publicAgent = agent.publicAgent
        let state = RunState(
            startingAgent: startingAgent,
            currentAgent: agent,
            originalInput: resultInput,
            sessionInputItems: sessionInputItems,
            modelInput: modelInput,
            newItems: newItems,
            modelResponses: modelResponses,
            runContext: context,
            trace: trace,
            lastResponseID: responseID,
            currentTurn: turn,
            maxTurns: config.maxTurns,
            interruptions: interruptions,
            pendingFunctionCalls: pendingFunctionCalls,
            pendingCustomToolCalls: pendingCustomToolCalls,
            pendingShellCalls: pendingShellCalls,
            pendingApplyPatchCalls: pendingApplyPatchCalls,
            inputGuardrailResults: inputGuardrailResults,
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults,
            toolUseTrackerSnapshot: toolUseTracker.snapshot(),
            generatedPromptCacheKey: promptCacheKeyResolver?.generatedKey,
            config: config,
            modelProvider: modelProvider
        )
        let replayItems = Self.replayItems(modelInput: modelInput, resultInput: resultInput)
        return RunResult(
            input: resultInput,
            finalOutput: "",
            lastAgentName: publicAgent.name,
            lastAgent: AgentSnapshot(publicAgent),
            trace: trace,
            newItems: newItems,
            modelResponses: modelResponses,
            usage: context.usage,
            responseID: responseID,
            inputGuardrailResults: inputGuardrailResults,
            outputGuardrailResults: [],
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults,
            interruptions: interruptions,
            resumeState: state,
            modelInputItems: replayItems,
            replayFromModelInputItems: replayItems != newItems
        )
    }
}
