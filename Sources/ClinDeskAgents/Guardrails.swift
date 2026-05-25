import Foundation

public struct GuardrailFunctionOutput: Equatable, Sendable {
    public var outputInfo: String
    public var tripwireTriggered: Bool

    public init(outputInfo: String = "", tripwireTriggered: Bool) {
        self.outputInfo = outputInfo
        self.tripwireTriggered = tripwireTriggered
    }
}

public struct InputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (RunContext<Context>, Agent<Context>, [ModelInputItem]) async throws -> GuardrailFunctionOutput

    public var name: String
    public var runInParallel: Bool
    private let check: Check

    public init(
        name: String,
        runInParallel: Bool = true,
        check: @escaping Check
    ) {
        self.name = name
        self.runInParallel = runInParallel
        self.check = check
    }

    public func run(context: RunContext<Context>, agent: Agent<Context>, input: [ModelInputItem]) async throws -> GuardrailFunctionOutput {
        try await check(context, agent, input)
    }
}

public struct OutputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (RunContext<Context>, Agent<Context>, String) async throws -> GuardrailFunctionOutput

    public var name: String
    private let check: Check

    public init(name: String, check: @escaping Check) {
        self.name = name
        self.check = check
    }

    public func run(context: RunContext<Context>, agent: Agent<Context>, output: String) async throws -> GuardrailFunctionOutput {
        try await check(context, agent, output)
    }
}

public struct ToolInputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (ToolContext<Context>) async throws -> GuardrailFunctionOutput

    public var name: String
    private let check: Check

    public init(name: String, check: @escaping Check) {
        self.name = name
        self.check = check
    }

    public func run(context: ToolContext<Context>) async throws -> GuardrailFunctionOutput {
        try await check(context)
    }
}

public struct ToolOutputGuardrail<Context: Sendable>: Sendable {
    public typealias Check = @Sendable (ToolContext<Context>, ToolOutput) async throws -> GuardrailFunctionOutput

    public var name: String
    private let check: Check

    public init(name: String, check: @escaping Check) {
        self.name = name
        self.check = check
    }

    public func run(context: ToolContext<Context>, output: ToolOutput) async throws -> GuardrailFunctionOutput {
        try await check(context, output)
    }
}
