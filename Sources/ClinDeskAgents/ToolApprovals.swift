import Foundation

public let defaultApprovalRejectionMessage = "Tool execution was not approved."

public struct CustomToolApprovalRequest<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var tool: CustomToolDescriptor
    public var call: CustomToolCall

    public init(context: RunContext<Context>, tool: CustomToolDescriptor, call: CustomToolCall) {
        self.context = context
        self.tool = tool
        self.call = call
    }
}

public struct ToolApprovalDecision: Equatable, Sendable {
    public var approve: Bool
    public var reason: String?

    public init(approve: Bool, reason: String? = nil) {
        self.approve = approve
        self.reason = reason
    }
}

public struct ToolOnApprovalRequest<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var item: ToolApprovalItem

    public init(context: RunContext<Context>, item: ToolApprovalItem) {
        self.context = context
        self.item = item
    }
}

public struct ToolApprovalRequest<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var tool: ToolDescriptor
    public var call: FunctionCall

    public init(context: RunContext<Context>, tool: ToolDescriptor, call: FunctionCall) {
        self.context = context
        self.tool = tool
        self.call = call
    }
}

public struct ToolApprovalItem: Equatable, Sendable {
    public var toolName: String
    public var callID: String
    public var arguments: JSONValue
    public var tool: ModelTool
    public var toolNamespace: String?
    public var allowBareNameAlias: Bool
    public var toolLookupKey: FunctionToolLookupKey?
    public var toolOrigin: ToolOrigin?

    public init(
        toolName: String,
        callID: String,
        arguments: JSONValue,
        tool: ModelTool,
        toolNamespace: String? = nil,
        allowBareNameAlias: Bool = false,
        toolLookupKey: FunctionToolLookupKey? = nil,
        toolOrigin: ToolOrigin? = nil
    ) {
        self.toolName = toolName
        self.callID = callID
        self.arguments = arguments
        self.tool = tool
        self.toolNamespace = toolNamespace
        self.allowBareNameAlias = allowBareNameAlias
        self.toolOrigin = toolOrigin

        if let toolLookupKey {
            self.toolLookupKey = toolLookupKey
        } else if case .function(let descriptor) = tool {
            let namespace = toolNamespace ?? descriptor.namespace
            if descriptor.deferLoading, descriptor.namespace?.isEmpty ?? true {
                self.toolLookupKey = .deferredTopLevel(descriptor.name)
            } else {
                self.toolLookupKey = ToolIdentity.functionToolLookupKey(
                    name: descriptor.name,
                    namespace: namespace
                )
            }
            self.toolNamespace = namespace
        } else {
            self.toolLookupKey = nil
        }
    }
}
