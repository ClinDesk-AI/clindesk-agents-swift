public struct ToolContext<Context: Sendable>: Sendable {
    public var runContext: RunContext<Context>
    public var call: FunctionCall
    public var agent: Agent<Context>?
    public var runConfig: RunConfig<Context>?

    public init(
        runContext: RunContext<Context>,
        call: FunctionCall,
        agent: Agent<Context>? = nil,
        runConfig: RunConfig<Context>? = nil
    ) {
        self.runContext = runContext
        self.call = call
        self.agent = agent
        self.runConfig = runConfig
    }

    public var toolName: String {
        call.name
    }

    public var toolCallID: String {
        call.callID
    }

    public var toolArguments: JSONValue {
        call.arguments
    }

    public var rawToolArguments: String {
        call.arguments.prettyPrinted()
    }

    public var toolNamespace: String? {
        guard let namespace = call.namespace, !namespace.isEmpty else {
            return nil
        }
        return namespace
    }

    public var qualifiedToolName: String {
        ToolIdentity.traceName(name: call.name, namespace: call.namespace) ?? call.name
    }
}

public struct ToolHookContext<Context: Sendable>: Sendable {
    public var runContext: RunContext<Context>
    public var toolName: String?
    public var toolCallID: String?
    public var toolInput: JSONValue?
    public var toolNamespace: String?
    public var functionCall: FunctionCall?
    public var customToolCall: CustomToolCall?

    public init(
        runContext: RunContext<Context>,
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolInput: JSONValue? = nil,
        toolNamespace: String? = nil,
        functionCall: FunctionCall? = nil,
        customToolCall: CustomToolCall? = nil
    ) {
        self.runContext = runContext
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.toolInput = toolInput
        self.toolNamespace = toolNamespace
        self.functionCall = functionCall
        self.customToolCall = customToolCall
    }

    public init(toolContext: ToolContext<Context>) {
        self.init(
            runContext: toolContext.runContext,
            toolName: toolContext.toolName,
            toolCallID: toolContext.toolCallID,
            toolInput: toolContext.toolArguments,
            toolNamespace: toolContext.toolNamespace,
            functionCall: toolContext.call
        )
    }

    public init(customToolContext: CustomToolContext<Context>) {
        self.init(
            runContext: customToolContext.runContext,
            toolName: customToolContext.toolName,
            toolCallID: customToolContext.toolCallID,
            toolInput: .string(customToolContext.toolInput),
            customToolCall: customToolContext.call
        )
    }

    public var rawToolInput: String? {
        toolInput?.prettyPrinted()
    }

    public var qualifiedToolName: String? {
        guard let toolName else {
            return nil
        }
        return ToolIdentity.traceName(name: toolName, namespace: toolNamespace) ?? toolName
    }
}

public struct CustomToolContext<Context: Sendable>: Sendable {
    public var runContext: RunContext<Context>
    public var call: CustomToolCall
    public var agent: Agent<Context>?
    public var runConfig: RunConfig<Context>?

    public init(
        runContext: RunContext<Context>,
        call: CustomToolCall,
        agent: Agent<Context>? = nil,
        runConfig: RunConfig<Context>? = nil
    ) {
        self.runContext = runContext
        self.call = call
        self.agent = agent
        self.runConfig = runConfig
    }

    public var toolName: String {
        call.name
    }

    public var toolCallID: String {
        call.callID
    }

    public var toolInput: String {
        call.input
    }
}
