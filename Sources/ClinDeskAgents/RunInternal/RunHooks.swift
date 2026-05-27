import Foundation

extension RunnerLoop {
    var modelTracing: ModelTracing {
        if config.tracingDisabled {
            return .disabled
        }
        return config.traceIncludeSensitiveData ? .enabled(includeData: true) : .enabled(includeData: false)
    }

    func callAgentStartHooks(
        context: RunContext<Context>,
        agent: Agent<Context>
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onAgentStart(context, publicAgent)
        try await publicAgent.hooks?.onStart(context, publicAgent)
    }

    func callAgentEndHooks(
        context: RunContext<Context>,
        agent: Agent<Context>,
        output: String
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onAgentEnd(context, publicAgent, output)
        try await publicAgent.hooks?.onEnd(context, publicAgent, output)
    }

    func callLLMStartHooks(
        context: RunContext<Context>,
        agent: Agent<Context>,
        instructions: String?,
        input: [ModelInputItem]
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onLLMStart(context, publicAgent, instructions, input)
        try await publicAgent.hooks?.onLLMStart(context, publicAgent, instructions, input)
    }

    func callLLMEndHooks(
        context: RunContext<Context>,
        agent: Agent<Context>,
        response: ModelResponse
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onLLMEnd(context, publicAgent, response)
        try await publicAgent.hooks?.onLLMEnd(context, publicAgent, response)
    }

    func callHandoffHooks(
        context: RunContext<Context>,
        from sourceAgent: Agent<Context>,
        to targetAgent: Agent<Context>
    ) async throws {
        try await config.hooks.onHandoff(context, sourceAgent, targetAgent)
        try await sourceAgent.hooks?.onHandoff(context, targetAgent, sourceAgent)
    }

    func callToolStartHooks(
        context: ToolHookContext<Context>,
        agent: Agent<Context>,
        tool: Tool<Context>
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onToolStart(context, publicAgent, tool)
        try await publicAgent.hooks?.onToolStart(context, publicAgent, tool)
    }

    func callToolEndHooks(
        context: ToolHookContext<Context>,
        agent: Agent<Context>,
        tool: Tool<Context>,
        output: String
    ) async throws {
        let publicAgent = agent.publicAgent
        try await config.hooks.onToolEnd(context, publicAgent, tool, output)
        try await publicAgent.hooks?.onToolEnd(context, publicAgent, tool, output)
    }
}
