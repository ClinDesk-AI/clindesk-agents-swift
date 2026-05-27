import Foundation

public struct LocalShellCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var action: JSONValue
    public var status: String?

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        action: JSONValue,
        status: String? = nil
    ) {
        self.id = id
        self.callID = callID
        self.action = action
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case action
        case status
    }
}

public struct LocalShellCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: String

    public init(callID: String, output: String) {
        self.callID = callID
        self.output = output
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case output
    }
}

public struct LocalShellCommandRequest<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var data: LocalShellCall

    public init(context: RunContext<Context>, data: LocalShellCall) {
        self.context = context
        self.data = data
    }
}

public struct LocalShellToolDescriptor: Codable, Equatable, Sendable {
    public var name: String

    public init(name: String = "local_shell") {
        self.name = name
    }
}

public struct LocalShellTool<Context: Sendable>: Sendable {
    public typealias Executor = @Sendable (
        LocalShellCommandRequest<Context>
    ) async throws -> String

    public var descriptor: LocalShellToolDescriptor
    public var executor: Executor

    public init(
        name: String = "local_shell",
        executor: @escaping Executor
    ) {
        self.descriptor = LocalShellToolDescriptor(name: name)
        self.executor = executor
    }

    public var name: String {
        descriptor.name
    }
}

public struct ShellActionRequest: Codable, Equatable, Sendable {
    public var commands: [String]
    public var timeoutMS: Int?
    public var maxOutputLength: Int?

    public init(
        commands: [String],
        timeoutMS: Int? = nil,
        maxOutputLength: Int? = nil
    ) {
        self.commands = commands
        self.timeoutMS = timeoutMS
        self.maxOutputLength = maxOutputLength
    }

    enum CodingKeys: String, CodingKey {
        case commands
        case timeoutMS = "timeout_ms"
        case maxOutputLength = "max_output_length"
    }
}

public struct ShellCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var action: ShellActionRequest
    public var status: String?
    public var raw: JSONValue?

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        action: ShellActionRequest,
        status: String? = nil,
        raw: JSONValue? = nil
    ) {
        self.id = id
        self.callID = callID
        self.action = action
        self.status = status
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case action
        case status
        case raw
    }
}

public enum ShellCallOutcomeType: String, Codable, Equatable, Sendable {
    case exit
    case timeout
}

public struct ShellCallOutcome: Codable, Equatable, Sendable {
    public var type: ShellCallOutcomeType
    public var exitCode: Int?

    public init(type: ShellCallOutcomeType, exitCode: Int? = nil) {
        self.type = type
        self.exitCode = exitCode
    }

    enum CodingKeys: String, CodingKey {
        case type
        case exitCode = "exit_code"
    }
}

public struct ShellCommandOutput: Codable, Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var outcome: ShellCallOutcome
    public var command: String?
    public var providerData: [String: JSONValue]?

    public init(
        stdout: String = "",
        stderr: String = "",
        outcome: ShellCallOutcome = ShellCallOutcome(type: .exit),
        command: String? = nil,
        providerData: [String: JSONValue]? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.outcome = outcome
        self.command = command
        self.providerData = providerData
    }

    public var exitCode: Int? {
        outcome.exitCode
    }

    public var status: String {
        outcome.type == .timeout ? "timeout" : "completed"
    }

    enum CodingKeys: String, CodingKey {
        case stdout
        case stderr
        case outcome
        case command
        case providerData = "provider_data"
    }
}

public struct ShellResult: Codable, Equatable, Sendable {
    public var output: [ShellCommandOutput]
    public var maxOutputLength: Int?
    public var providerData: [String: JSONValue]?

    public init(
        output: [ShellCommandOutput],
        maxOutputLength: Int? = nil,
        providerData: [String: JSONValue]? = nil
    ) {
        self.output = output
        self.maxOutputLength = maxOutputLength
        self.providerData = providerData
    }
}

public enum ShellToolOutput: Equatable, Sendable {
    case text(String)
    case result(ShellResult)
}

public struct ShellCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: JSONValue
    public var status: String?

    public init(callID: String, output: JSONValue, status: String? = nil) {
        self.callID = callID
        self.output = output
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case output
        case status
    }
}

public struct ShellCommandRequest<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var data: ShellCall

    public init(context: RunContext<Context>, data: ShellCall) {
        self.context = context
        self.data = data
    }
}

public struct ShellToolDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var environment: JSONValue

    public init(name: String = "shell") {
        self.name = name
        self.environment = ["type": "local"]
    }
}

public enum ShellToolApproval<Context: Sendable>: Sendable {
    case never
    case always
    case dynamic(@Sendable (RunContext<Context>, ShellActionRequest, String) async throws -> Bool)

    var isNever: Bool {
        if case .never = self {
            return true
        }
        return false
    }
}

public struct ShellTool<Context: Sendable>: Sendable {
    public typealias Executor = @Sendable (
        ShellCommandRequest<Context>
    ) async throws -> ShellToolOutput
    public typealias OnApproval = @Sendable (
        ToolOnApprovalRequest<Context>
    ) async throws -> ToolApprovalDecision?

    public var descriptor: ShellToolDescriptor
    public var executor: Executor
    public var needsApproval: ShellToolApproval<Context>
    public var onApproval: OnApproval?

    public init(
        executor: @escaping Executor,
        name: String = "shell",
        needsApproval: ShellToolApproval<Context> = .never,
        onApproval: OnApproval? = nil
    ) throws {
        self.descriptor = ShellToolDescriptor(name: name)
        self.executor = executor
        self.needsApproval = needsApproval
        self.onApproval = onApproval
    }

    public var name: String {
        descriptor.name
    }

    public var type: String {
        "shell"
    }

    public var isLocal: Bool {
        true
    }
}
