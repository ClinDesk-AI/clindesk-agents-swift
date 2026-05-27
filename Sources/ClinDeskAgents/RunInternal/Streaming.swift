struct RunnerStreamEvent<Context: Sendable>: Sendable {
    var event: StreamEvent<Context>
    var agent: Agent<Context>
}

typealias RunnerStreamEventHandler<Context: Sendable> = @Sendable (
    RunnerStreamEvent<Context>
) async -> Void

enum RunnerStreaming {
    static func rawResponseStarted<Context: Sendable>(
        agent: Agent<Context>
    ) -> RunnerStreamEvent<Context> {
        RunnerStreamEvent(
            event: .modelResponseEvent(ModelResponseStreamEvent(data: .started)),
            agent: agent
        )
    }

    static func rawResponseCompleted<Context: Sendable>(
        _ response: ModelResponse,
        agent: Agent<Context>
    ) -> RunnerStreamEvent<Context> {
        RunnerStreamEvent(
            event: .modelResponseEvent(ModelResponseStreamEvent(data: .completed(response))),
            agent: agent
        )
    }

    static func agentUpdated<Context: Sendable>(
        _ agent: Agent<Context>
    ) -> RunnerStreamEvent<Context> {
        RunnerStreamEvent(
            event: .agentUpdatedStreamEvent(AgentUpdatedStreamEvent(newAgent: agent)),
            agent: agent
        )
    }

    static func runItemStreamEvent<Context: Sendable>(
        for item: RunItem<Context>
    ) -> RunItemStreamEvent<Context>? {
        let name: RunItemStreamEventName
        switch item {
        case .messageOutputItem:
            name = .messageOutputCreated
        case .handoffCallItem:
            name = .handoffRequested
        case .handoffOutputItem:
            name = .handoffOccurred
        case .toolCallItem,
                .customToolCallItem,
                .computerCallItem,
                .localShellCallItem,
                .shellCallItem,
                .applyPatchCallItem:
            name = .toolCalled
        case .toolCallOutputItem,
                .customToolCallOutputItem,
                .computerCallOutputItem,
                .localShellCallOutputItem,
                .shellCallOutputItem,
                .applyPatchCallOutputItem:
            name = .toolOutput
        case .reasoningItem:
            name = .reasoningItemCreated
        }
        return RunItemStreamEvent(name: name, item: item)
    }

    static func runItemStreamEvent<Context: Sendable>(
        for outputItem: ModelInputItem,
        agent: Agent<Context>,
        handoffToolNames: Set<String> = []
    ) -> RunItemStreamEvent<Context>? {
        switch outputItem {
        case .message(let message):
            return runItemStreamEvent(for: .messageOutputItem(MessageOutputItem(
                agent: agent,
                rawItem: message
            )))
        case .functionCall(let call):
            if handoffToolNames.contains(call.name) {
                return runItemStreamEvent(for: .handoffCallItem(HandoffCallItem(
                    agent: agent,
                    rawItem: call
                )))
            }
            return runItemStreamEvent(for: .toolCallItem(ToolCallItem(
                agent: agent,
                rawItem: call,
                toolOrigin: call.toolOrigin
            )))
        case .customToolCall(let call):
            return runItemStreamEvent(for: .customToolCallItem(CustomToolCallItem(
                agent: agent,
                rawItem: call
            )))
        case .computerCall(let call):
            return runItemStreamEvent(for: .computerCallItem(ComputerCallItem(
                agent: agent,
                rawItem: call
            )))
        case .localShellCall(let call):
            return runItemStreamEvent(for: .localShellCallItem(LocalShellCallItem(
                agent: agent,
                rawItem: call
            )))
        case .shellCall(let call):
            return runItemStreamEvent(for: .shellCallItem(ShellCallItem(
                agent: agent,
                rawItem: call
            )))
        case .applyPatchCall(let call):
            return runItemStreamEvent(for: .applyPatchCallItem(ApplyPatchCallItem(
                agent: agent,
                rawItem: call
            )))
        case .functionCallOutput(let output):
            return toolOutputEvent(agent: agent, output: output)
        case .customToolCallOutput(let output):
            return runItemStreamEvent(for: .customToolCallOutputItem(CustomToolCallOutputItem(
                agent: agent,
                rawItem: output,
                output: output.output
            )))
        case .computerCallOutput(let output):
            return runItemStreamEvent(for: .computerCallOutputItem(ComputerCallOutputItem(
                agent: agent,
                rawItem: output,
                output: output.output
            )))
        case .localShellCallOutput(let output):
            return runItemStreamEvent(for: .localShellCallOutputItem(LocalShellCallOutputItem(
                agent: agent,
                rawItem: output,
                output: output.output
            )))
        case .shellCallOutput(let output):
            return runItemStreamEvent(for: .shellCallOutputItem(ShellCallOutputItem(
                agent: agent,
                rawItem: output,
                output: output.output
            )))
        case .applyPatchCallOutput(let output):
            return runItemStreamEvent(for: .applyPatchCallOutputItem(ApplyPatchCallOutputItem(
                agent: agent,
                rawItem: output,
                output: output.output
            )))
        case .reasoning(let reasoning):
            return runItemStreamEvent(for: .reasoningItem(ReasoningItem(
                agent: agent,
                rawItem: reasoning
            )))
        case .refusal, .raw:
            return nil
        }
    }

    static func handoffOutputEvent<Context: Sendable>(
        from sourceAgent: Agent<Context>,
        to targetAgent: Agent<Context>,
        output: FunctionCallOutput?
    ) -> RunItemStreamEvent<Context>? {
        runItemStreamEvent(for: .handoffOutputItem(HandoffOutputItem(
            agent: targetAgent,
            rawItem: output,
            sourceAgent: sourceAgent,
            targetAgent: targetAgent
        )))
    }

    static func toolOutputEvent<Context: Sendable>(
        agent: Agent<Context>,
        call: FunctionCall,
        output: ToolOutput
    ) -> RunItemStreamEvent<Context>? {
        toolOutputEvent(
            agent: agent,
            output: ItemHelpers.toolCallOutputItem(toolCall: call, output: output)
        )
    }

    static func toolOutputEvent<Context: Sendable>(
        agent: Agent<Context>,
        output: FunctionCallOutput
    ) -> RunItemStreamEvent<Context>? {
        runItemStreamEvent(for: .toolCallOutputItem(ToolCallOutputItem(
            agent: agent,
            rawItem: output,
            output: output.output,
            toolOrigin: output.toolOrigin
        )))
    }
}

extension RunnerLoop {
    func emitStreamEvent(_ event: RunnerStreamEvent<Context>) async {
        await config.streamEventHandler?(event)
    }

    func emitStreamEvent(_ event: StreamEvent<Context>, agent: Agent<Context>) async {
        await emitStreamEvent(RunnerStreamEvent(event: event, agent: agent))
    }

    func emitRunItemStreamEvent(_ event: RunItemStreamEvent<Context>?) async {
        guard let event else {
            return
        }
        await emitStreamEvent(.runItemStreamEvent(event), agent: event.item.agent)
    }
}
