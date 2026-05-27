import Foundation

public enum ToolGuardrailBehavior: Equatable, Sendable {
    case allow
    case rejectContent(message: String)
    case raiseException
}

public struct ToolGuardrailFunctionOutput: Equatable, Sendable {
    public var outputInfo: String
    public var behavior: ToolGuardrailBehavior

    public init(
        outputInfo: String = "",
        behavior: ToolGuardrailBehavior = .allow
    ) {
        self.outputInfo = outputInfo
        self.behavior = behavior
    }

    public static func allow(outputInfo: String = "") -> ToolGuardrailFunctionOutput {
        ToolGuardrailFunctionOutput(outputInfo: outputInfo, behavior: .allow)
    }

    public static func rejectContent(
        message: String,
        outputInfo: String = ""
    ) -> ToolGuardrailFunctionOutput {
        ToolGuardrailFunctionOutput(
            outputInfo: outputInfo,
            behavior: .rejectContent(message: message)
        )
    }

    public static func raiseException(outputInfo: String = "") -> ToolGuardrailFunctionOutput {
        ToolGuardrailFunctionOutput(outputInfo: outputInfo, behavior: .raiseException)
    }

    var guardrailFunctionOutput: GuardrailFunctionOutput {
        GuardrailFunctionOutput(
            outputInfo: outputInfo,
            tripwireTriggered: behavior == .raiseException
        )
    }
}

public struct ToolInputGuardrailResult: Equatable, Sendable {
    public var guardrailName: String
    public var toolName: String
    public var callID: String
    public var output: ToolGuardrailFunctionOutput

    public init(
        guardrailName: String,
        toolName: String,
        callID: String,
        output: ToolGuardrailFunctionOutput
    ) {
        self.guardrailName = guardrailName
        self.toolName = toolName
        self.callID = callID
        self.output = output
    }
}

public struct ToolOutputGuardrailResult: Equatable, Sendable {
    public var guardrailName: String
    public var toolName: String
    public var callID: String
    public var output: ToolGuardrailFunctionOutput

    public init(
        guardrailName: String,
        toolName: String,
        callID: String,
        output: ToolGuardrailFunctionOutput
    ) {
        self.guardrailName = guardrailName
        self.toolName = toolName
        self.callID = callID
        self.output = output
    }
}

public struct ToolInputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (ToolContext<Context>) async throws -> ToolGuardrailFunctionOutput

    public var name: String
    private let check: Check

    public init(name: String, check: @escaping Check) {
        self.name = name
        self.check = check
    }

    public func run(context: ToolContext<Context>) async throws -> ToolGuardrailFunctionOutput {
        try await check(context)
    }
}

public struct ToolOutputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (ToolContext<Context>, ToolOutput) async throws -> ToolGuardrailFunctionOutput

    public var name: String
    private let check: Check

    public init(name: String, check: @escaping Check) {
        self.name = name
        self.check = check
    }

    public func run(context: ToolContext<Context>, output: ToolOutput) async throws -> ToolGuardrailFunctionOutput {
        try await check(context, output)
    }
}
