import Foundation

struct NewModelResponseResult<Context: Sendable>: Sendable {
    var response: ModelResponse
    var runContext: RunContext<Context>
}

extension RunnerLoop {
    func getNewResponse(
        agent: Agent<Context>,
        runContext: RunContext<Context>,
        modelInput: [ModelInputItem],
        tools: [Tool<Context>],
        handoffs: [Handoff<Context>],
        toolUseTracker: AgentToolUseTracker<Context>,
        promptCacheKeyResolver: inout PromptCacheKeyResolver<Context>,
        trace: inout Trace
    ) async throws -> NewModelResponseResult<Context> {
        let model = try await resolveModel(for: agent)
        let instructions = try await agent.instructions?.resolve(context: runContext, agent: agent)
        let publicAgent = agent.publicAgent
        let prompt = try await agent.prompt?.resolve(context: runContext, agent: publicAgent)
        var settings = resolvedModelSettings(for: agent)
        if agent.resetToolChoice && toolUseTracker.hasUsedTools(agent) {
            settings.toolChoice = nil
        }
        let modelInputData = try await filteredModelInputData(
            agent: agent,
            context: runContext,
            input: modelInput,
            instructions: instructions
        )
        let promptCacheKey = promptCacheKeyResolver.resolve(
            modelSettings: settings,
            model: model,
            session: config.session,
            groupID: config.groupID
        )
        settings = PromptCacheKeyResolver<Context>.modelSettingsWithPromptCacheKey(
            settings,
            promptCacheKey: promptCacheKey
        )

        await emitStreamEvent(RunnerStreaming.rawResponseStarted(agent: publicAgent))
        try await callLLMStartHooks(
            context: runContext,
            agent: agent,
            instructions: modelInputData.instructions,
            input: modelInputData.input
        )
        trace.items.append(.modelRequest(publicAgent.name))
        let modelRequest = ModelRequest(
            instructions: modelInputData.instructions,
            prompt: prompt,
            input: modelInputData.input,
            context: runContext,
            settings: settings,
            tools: tools.map(\.modelTool),
            handoffs: handoffs.map(\.descriptor),
            outputSchema: agent.outputSchema,
            tracing: modelTracing
        )
        let response = try await ModelRetry.getResponseWithRetry(
            getResponse: {
                try await model.getResponse(modelRequest)
            },
            retrySettings: settings.retry,
            getRetryAdvice: { request in
                model.retryAdvice(for: request)
            }
        )

        var updatedContext = runContext
        updatedContext.usage.add(response.usage)
        trace.items.append(.modelResponse(response))
        await emitStreamEvent(RunnerStreaming.rawResponseCompleted(response, agent: publicAgent))
        try await callLLMEndHooks(context: updatedContext, agent: agent, response: response)

        return NewModelResponseResult(
            response: response,
            runContext: updatedContext
        )
    }
}
