import Foundation

public enum ToolUseBehavior<Context: Sendable>: Sendable {
    public typealias Resolver = @Sendable (RunContext<Context>, [ToolRunResult]) async throws -> ToolsToFinalOutputResult

    case runModelAgain
    case stopOnFirstTool
    case stopAtTools(Set<String>)
    case custom(Resolver)
}

public struct ToolRunResult: Equatable, Sendable {
    public var call: FunctionCall
    public var output: ToolOutput
    public var inputGuardrailResults: [ToolInputGuardrailResult]
    public var outputGuardrailResults: [ToolOutputGuardrailResult]
    public var interruptions: [ToolApprovalItem]
    public var toolOrigin: ToolOrigin?

    public init(
        call: FunctionCall,
        output: ToolOutput,
        inputGuardrailResults: [ToolInputGuardrailResult] = [],
        outputGuardrailResults: [ToolOutputGuardrailResult] = [],
        interruptions: [ToolApprovalItem] = [],
        toolOrigin: ToolOrigin? = nil
    ) {
        self.call = call
        self.output = output
        self.inputGuardrailResults = inputGuardrailResults
        self.outputGuardrailResults = outputGuardrailResults
        self.interruptions = interruptions
        self.toolOrigin = toolOrigin ?? call.toolOrigin
    }
}

public struct CustomToolRunResult: Equatable, Sendable {
    public var call: CustomToolCall
    public var output: String

    public init(call: CustomToolCall, output: String) {
        self.call = call
        self.output = output
    }
}

public struct ComputerRunResult: Equatable, Sendable {
    public var call: ComputerCall
    public var imageURL: String
    public var acknowledgedSafetyChecks: [PendingComputerSafetyCheck]?

    public init(
        call: ComputerCall,
        imageURL: String,
        acknowledgedSafetyChecks: [PendingComputerSafetyCheck]? = nil
    ) {
        self.call = call
        self.imageURL = imageURL
        self.acknowledgedSafetyChecks = acknowledgedSafetyChecks
    }
}

public struct LocalShellRunResult: Equatable, Sendable {
    public var call: LocalShellCall
    public var output: String

    public init(call: LocalShellCall, output: String) {
        self.call = call
        self.output = output
    }
}

public struct ShellRunResult: Equatable, Sendable {
    public var call: ShellCall
    public var output: JSONValue
    public var status: String

    public init(call: ShellCall, output: JSONValue, status: String) {
        self.call = call
        self.output = output
        self.status = status
    }
}

public struct ApplyPatchRunResult: Equatable, Sendable {
    public var call: ApplyPatchCall
    public var status: ApplyPatchStatus
    public var output: String

    public init(call: ApplyPatchCall, status: ApplyPatchStatus, output: String) {
        self.call = call
        self.status = status
        self.output = output
    }
}

public struct ToolsToFinalOutputResult: Equatable, Sendable {
    public var isFinalOutput: Bool
    public var finalOutput: String?

    public init(isFinalOutput: Bool, finalOutput: String? = nil) {
        self.isFinalOutput = isFinalOutput
        self.finalOutput = finalOutput
    }
}
