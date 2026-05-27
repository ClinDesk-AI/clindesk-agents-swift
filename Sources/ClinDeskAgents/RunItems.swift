public struct MessageOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: AgentMessage

    public var type: String {
        "message_output_item"
    }

    public init(agent: Agent<Context>, rawItem: AgentMessage) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .message(rawItem)
    }
}

public struct HandoffCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: FunctionCall

    public var type: String {
        "handoff_call_item"
    }

    public init(agent: Agent<Context>, rawItem: FunctionCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .functionCall(rawItem)
    }
}

public struct HandoffOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: FunctionCallOutput?
    public var sourceAgent: Agent<Context>
    public var targetAgent: Agent<Context>

    public var type: String {
        "handoff_output_item"
    }

    public init(
        agent: Agent<Context>,
        rawItem: FunctionCallOutput?,
        sourceAgent: Agent<Context>,
        targetAgent: Agent<Context>
    ) {
        self.agent = agent
        self.rawItem = rawItem
        self.sourceAgent = sourceAgent
        self.targetAgent = targetAgent
    }

    public func toInputItem() -> ModelInputItem? {
        rawItem.map(ModelInputItem.functionCallOutput)
    }
}

public struct ToolCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: FunctionCall
    public var description: String?
    public var title: String?
    public var toolOrigin: ToolOrigin?

    public var type: String {
        "tool_call_item"
    }

    public var toolName: String {
        rawItem.name
    }

    public var callID: String {
        rawItem.callID
    }

    public init(
        agent: Agent<Context>,
        rawItem: FunctionCall,
        description: String? = nil,
        title: String? = nil,
        toolOrigin: ToolOrigin? = nil
    ) {
        self.agent = agent
        self.rawItem = rawItem
        self.description = description
        self.title = title
        self.toolOrigin = toolOrigin
    }

    public func toInputItem() -> ModelInputItem {
        .functionCall(rawItem)
    }
}

public struct ToolCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: FunctionCallOutput
    public var output: JSONValue
    public var toolOrigin: ToolOrigin?

    public var type: String {
        "tool_call_output_item"
    }

    public var callID: String {
        rawItem.callID
    }

    public init(
        agent: Agent<Context>,
        rawItem: FunctionCallOutput,
        output: JSONValue,
        toolOrigin: ToolOrigin? = nil
    ) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
        self.toolOrigin = toolOrigin
    }

    public func toInputItem() -> ModelInputItem {
        .functionCallOutput(rawItem)
    }
}

public struct CustomToolCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: CustomToolCall

    public var type: String {
        "tool_call_item"
    }

    public init(agent: Agent<Context>, rawItem: CustomToolCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .customToolCall(rawItem)
    }
}

public struct CustomToolCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: CustomToolCallOutput
    public var output: String

    public var type: String {
        "tool_call_output_item"
    }

    public init(agent: Agent<Context>, rawItem: CustomToolCallOutput, output: String) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
    }

    public func toInputItem() -> ModelInputItem {
        .customToolCallOutput(rawItem)
    }
}

public struct ComputerCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ComputerCall

    public var type: String {
        "tool_call_item"
    }

    public init(agent: Agent<Context>, rawItem: ComputerCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .computerCall(rawItem)
    }
}

public struct ComputerCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ComputerCallOutput
    public var output: JSONValue

    public var type: String {
        "tool_call_output_item"
    }

    public init(agent: Agent<Context>, rawItem: ComputerCallOutput, output: JSONValue) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
    }

    public func toInputItem() -> ModelInputItem {
        .computerCallOutput(rawItem)
    }
}

public struct LocalShellCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: LocalShellCall

    public var type: String {
        "tool_call_item"
    }

    public init(agent: Agent<Context>, rawItem: LocalShellCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .localShellCall(rawItem)
    }
}

public struct LocalShellCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: LocalShellCallOutput
    public var output: String

    public var type: String {
        "tool_call_output_item"
    }

    public init(agent: Agent<Context>, rawItem: LocalShellCallOutput, output: String) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
    }

    public func toInputItem() -> ModelInputItem {
        .localShellCallOutput(rawItem)
    }
}

public struct ShellCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ShellCall

    public var type: String {
        "tool_call_item"
    }

    public init(agent: Agent<Context>, rawItem: ShellCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .shellCall(rawItem)
    }
}

public struct ShellCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ShellCallOutput
    public var output: JSONValue

    public var type: String {
        "tool_call_output_item"
    }

    public init(agent: Agent<Context>, rawItem: ShellCallOutput, output: JSONValue) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
    }

    public func toInputItem() -> ModelInputItem {
        .shellCallOutput(rawItem)
    }
}

public struct ApplyPatchCallItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ApplyPatchCall

    public var type: String {
        "tool_call_item"
    }

    public init(agent: Agent<Context>, rawItem: ApplyPatchCall) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .applyPatchCall(rawItem)
    }
}

public struct ApplyPatchCallOutputItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: ApplyPatchCallOutput
    public var output: String

    public var type: String {
        "tool_call_output_item"
    }

    public init(agent: Agent<Context>, rawItem: ApplyPatchCallOutput, output: String) {
        self.agent = agent
        self.rawItem = rawItem
        self.output = output
    }

    public func toInputItem() -> ModelInputItem {
        .applyPatchCallOutput(rawItem)
    }
}

public struct ReasoningItem<Context: Sendable>: Sendable {
    public var agent: Agent<Context>
    public var rawItem: JSONValue

    public var type: String {
        "reasoning_item"
    }

    public init(agent: Agent<Context>, rawItem: JSONValue) {
        self.agent = agent
        self.rawItem = rawItem
    }

    public func toInputItem() -> ModelInputItem {
        .reasoning(rawItem)
    }
}

public enum RunItem<Context: Sendable>: Sendable {
    case messageOutputItem(MessageOutputItem<Context>)
    case handoffCallItem(HandoffCallItem<Context>)
    case handoffOutputItem(HandoffOutputItem<Context>)
    case toolCallItem(ToolCallItem<Context>)
    case toolCallOutputItem(ToolCallOutputItem<Context>)
    case customToolCallItem(CustomToolCallItem<Context>)
    case customToolCallOutputItem(CustomToolCallOutputItem<Context>)
    case computerCallItem(ComputerCallItem<Context>)
    case computerCallOutputItem(ComputerCallOutputItem<Context>)
    case localShellCallItem(LocalShellCallItem<Context>)
    case localShellCallOutputItem(LocalShellCallOutputItem<Context>)
    case shellCallItem(ShellCallItem<Context>)
    case shellCallOutputItem(ShellCallOutputItem<Context>)
    case applyPatchCallItem(ApplyPatchCallItem<Context>)
    case applyPatchCallOutputItem(ApplyPatchCallOutputItem<Context>)
    case reasoningItem(ReasoningItem<Context>)

    public var type: String {
        switch self {
        case .messageOutputItem(let item):
            return item.type
        case .handoffCallItem(let item):
            return item.type
        case .handoffOutputItem(let item):
            return item.type
        case .toolCallItem(let item):
            return item.type
        case .toolCallOutputItem(let item):
            return item.type
        case .customToolCallItem(let item):
            return item.type
        case .customToolCallOutputItem(let item):
            return item.type
        case .computerCallItem(let item):
            return item.type
        case .computerCallOutputItem(let item):
            return item.type
        case .localShellCallItem(let item):
            return item.type
        case .localShellCallOutputItem(let item):
            return item.type
        case .shellCallItem(let item):
            return item.type
        case .shellCallOutputItem(let item):
            return item.type
        case .applyPatchCallItem(let item):
            return item.type
        case .applyPatchCallOutputItem(let item):
            return item.type
        case .reasoningItem(let item):
            return item.type
        }
    }

    public var agent: Agent<Context> {
        switch self {
        case .messageOutputItem(let item):
            return item.agent
        case .handoffCallItem(let item):
            return item.agent
        case .handoffOutputItem(let item):
            return item.agent
        case .toolCallItem(let item):
            return item.agent
        case .toolCallOutputItem(let item):
            return item.agent
        case .customToolCallItem(let item):
            return item.agent
        case .customToolCallOutputItem(let item):
            return item.agent
        case .computerCallItem(let item):
            return item.agent
        case .computerCallOutputItem(let item):
            return item.agent
        case .localShellCallItem(let item):
            return item.agent
        case .localShellCallOutputItem(let item):
            return item.agent
        case .shellCallItem(let item):
            return item.agent
        case .shellCallOutputItem(let item):
            return item.agent
        case .applyPatchCallItem(let item):
            return item.agent
        case .applyPatchCallOutputItem(let item):
            return item.agent
        case .reasoningItem(let item):
            return item.agent
        }
    }

    public func toInputItem() -> ModelInputItem? {
        switch self {
        case .messageOutputItem(let item):
            return item.toInputItem()
        case .handoffCallItem(let item):
            return item.toInputItem()
        case .handoffOutputItem(let item):
            return item.toInputItem()
        case .toolCallItem(let item):
            return item.toInputItem()
        case .toolCallOutputItem(let item):
            return item.toInputItem()
        case .customToolCallItem(let item):
            return item.toInputItem()
        case .customToolCallOutputItem(let item):
            return item.toInputItem()
        case .computerCallItem(let item):
            return item.toInputItem()
        case .computerCallOutputItem(let item):
            return item.toInputItem()
        case .localShellCallItem(let item):
            return item.toInputItem()
        case .localShellCallOutputItem(let item):
            return item.toInputItem()
        case .shellCallItem(let item):
            return item.toInputItem()
        case .shellCallOutputItem(let item):
            return item.toInputItem()
        case .applyPatchCallItem(let item):
            return item.toInputItem()
        case .applyPatchCallOutputItem(let item):
            return item.toInputItem()
        case .reasoningItem(let item):
            return item.toInputItem()
        }
    }
}
