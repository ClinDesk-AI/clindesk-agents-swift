import Foundation

public struct CustomTool<Context: Sendable>: Sendable {
    public typealias Executor = @Sendable (CustomToolContext<Context>, String) async throws -> String
    public typealias Approval = @Sendable (CustomToolApprovalRequest<Context>) async throws -> Bool
    public typealias OnApproval = @Sendable (ToolOnApprovalRequest<Context>) async throws -> ToolApprovalDecision?

    public var descriptor: CustomToolDescriptor
    public var needsApproval: Approval
    public var onApproval: OnApproval?
    private let executor: Executor

    public init(
        name: String,
        description: String,
        format: JSONValue? = nil,
        deferLoading: Bool = false,
        needsApproval: @escaping Approval = { _ in false },
        onApproval: OnApproval? = nil,
        execute: @escaping Executor
    ) {
        self.descriptor = CustomToolDescriptor(
            name: name,
            description: description,
            format: format,
            deferLoading: deferLoading
        )
        self.needsApproval = needsApproval
        self.onApproval = onApproval
        self.executor = execute
    }

    public var name: String {
        descriptor.name
    }

    public func run(_ context: CustomToolContext<Context>) async throws -> String {
        try await executor(context, context.call.input)
    }
}
