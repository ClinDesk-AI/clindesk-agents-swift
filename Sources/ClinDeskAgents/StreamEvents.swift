public struct ModelResponseStreamEvent: Sendable {
    public var data: ModelStreamEvent

    public var type: String {
        "model_response_event"
    }

    public init(data: ModelStreamEvent) {
        self.data = data
    }
}

public enum RunItemStreamEventName: String, Sendable {
    case messageOutputCreated = "message_output_created"
    case handoffRequested = "handoff_requested"
    case handoffOccurred = "handoff_occured"
    case toolCalled = "tool_called"
    case toolOutput = "tool_output"
    case reasoningItemCreated = "reasoning_item_created"
}

public struct RunItemStreamEvent<Context: Sendable>: Sendable {
    public var name: RunItemStreamEventName
    public var item: RunItem<Context>

    public var type: String {
        "run_item_stream_event"
    }

    public init(name: RunItemStreamEventName, item: RunItem<Context>) {
        self.name = name
        self.item = item
    }
}

public struct AgentUpdatedStreamEvent<Context: Sendable>: Sendable {
    public var newAgent: Agent<Context>

    public var type: String {
        "agent_updated_stream_event"
    }

    public init(newAgent: Agent<Context>) {
        self.newAgent = newAgent
    }
}

public enum StreamEvent<Context: Sendable>: Sendable {
    case modelResponseEvent(ModelResponseStreamEvent)
    case runItemStreamEvent(RunItemStreamEvent<Context>)
    case agentUpdatedStreamEvent(AgentUpdatedStreamEvent<Context>)
}

public typealias RunStreamEvent<Context: Sendable> = StreamEvent<Context>

public struct AgentToolStreamEvent<Context: Sendable>: Sendable {
    public var event: StreamEvent<Context>
    public var agent: Agent<Context>
    public var toolCall: FunctionCall?

    public init(
        event: StreamEvent<Context>,
        agent: Agent<Context>,
        toolCall: FunctionCall?
    ) {
        self.event = event
        self.agent = agent
        self.toolCall = toolCall
    }
}

public typealias AgentToolStreamHandler<Context: Sendable> = @Sendable (
    AgentToolStreamEvent<Context>
) async throws -> Void
