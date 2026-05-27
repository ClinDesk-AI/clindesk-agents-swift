enum AgentToolStreaming {
    static func configure<Context: Sendable>(
        runConfig: inout RunConfig<Context>,
        onStream: @escaping AgentToolStreamHandler<Context>,
        toolCall: FunctionCall
    ) {
        let base = runConfig.streamEventHandler
        runConfig.streamEventHandler = { event in
            await base?(event)
            await notify(
                onStream,
                event: event.event,
                agent: event.agent,
                toolCall: toolCall
            )
        }
    }

    private static func notify<Context: Sendable>(
        _ onStream: AgentToolStreamHandler<Context>,
        event: RunStreamEvent<Context>,
        agent: Agent<Context>,
        toolCall: FunctionCall
    ) async {
        do {
            try await onStream(AgentToolStreamEvent(
                event: event,
                agent: agent,
                toolCall: toolCall
            ))
        } catch {
            // Match upstream: stream-handler failures are non-fatal to the agent tool run.
        }
    }
}
