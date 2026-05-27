import Foundation

public enum ApplyPatchOperationType: String, Codable, Equatable, Sendable {
    case createFile = "create_file"
    case updateFile = "update_file"
    case deleteFile = "delete_file"
}

public struct ApplyPatchOperation: Codable, Equatable, Sendable {
    public var type: ApplyPatchOperationType
    public var path: String
    public var diff: String?
    public var moveTo: String?

    public init(
        type: ApplyPatchOperationType,
        path: String,
        diff: String? = nil,
        moveTo: String? = nil
    ) {
        self.type = type
        self.path = path
        self.diff = diff
        self.moveTo = moveTo
    }

    enum CodingKeys: String, CodingKey {
        case type
        case path
        case diff
        case moveTo = "move_to"
    }
}

public struct ApplyPatchCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var operations: [ApplyPatchOperation]
    public var status: String?
    public var raw: JSONValue?

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        operations: [ApplyPatchOperation],
        status: String? = nil,
        raw: JSONValue? = nil
    ) {
        self.id = id
        self.callID = callID
        self.operations = operations
        self.status = status
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case operations
        case status
        case raw
    }
}

public enum ApplyPatchStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
}

public struct ApplyPatchResult: Codable, Equatable, Sendable {
    public var status: ApplyPatchStatus?
    public var output: String?

    public init(status: ApplyPatchStatus? = nil, output: String? = nil) {
        self.status = status
        self.output = output
    }
}

public struct ApplyPatchCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var status: ApplyPatchStatus
    public var output: String

    public init(callID: String, status: ApplyPatchStatus, output: String = "") {
        self.callID = callID
        self.status = status
        self.output = output
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case status
        case output
    }
}

public protocol ApplyPatchEditor: Sendable {
    func createFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult?
    func updateFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult?
    func deleteFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult?
}

public struct ApplyPatchToolDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var toolConfig: JSONValue?

    public init(name: String = "apply_patch", toolConfig: JSONValue? = nil) {
        self.name = name
        self.toolConfig = toolConfig
    }
}

public enum ApplyPatchToolApproval<Context: Sendable>: Sendable {
    case never
    case always
    case dynamic(@Sendable (RunContext<Context>, ApplyPatchOperation, String) async throws -> Bool)
}

public struct ApplyPatchTool<Context: Sendable>: Sendable {
    public typealias OnApproval = @Sendable (
        ToolOnApprovalRequest<Context>
    ) async throws -> ToolApprovalDecision?

    public var editor: any ApplyPatchEditor
    public var descriptor: ApplyPatchToolDescriptor
    public var needsApproval: ApplyPatchToolApproval<Context>
    public var onApproval: OnApproval?

    public init(
        editor: any ApplyPatchEditor,
        name: String = "apply_patch",
        toolConfig: JSONValue? = nil,
        needsApproval: ApplyPatchToolApproval<Context> = .never,
        onApproval: OnApproval? = nil
    ) {
        self.editor = editor
        self.descriptor = ApplyPatchToolDescriptor(name: name, toolConfig: toolConfig)
        self.needsApproval = needsApproval
        self.onApproval = onApproval
    }

    public var name: String {
        descriptor.name
    }

    public var type: String {
        "apply_patch"
    }
}
