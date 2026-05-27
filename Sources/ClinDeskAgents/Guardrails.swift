import Foundation

public struct GuardrailFunctionOutput: Equatable, Sendable {
    public var outputInfo: String
    public var tripwireTriggered: Bool

    public init(
        outputInfo: String = "",
        tripwireTriggered: Bool
    ) {
        self.outputInfo = outputInfo
        self.tripwireTriggered = tripwireTriggered
    }
}

public struct InputGuardrailResult: Equatable, Sendable {
    public var guardrailName: String
    public var output: GuardrailFunctionOutput

    public init(guardrailName: String, output: GuardrailFunctionOutput) {
        self.guardrailName = guardrailName
        self.output = output
    }
}

public struct OutputGuardrailResult: Equatable, Sendable {
    public var guardrailName: String
    public var agentName: String
    public var agentOutput: String
    public var output: GuardrailFunctionOutput

    public init(
        guardrailName: String,
        agentName: String,
        agentOutput: String,
        output: GuardrailFunctionOutput
    ) {
        self.guardrailName = guardrailName
        self.agentName = agentName
        self.agentOutput = agentOutput
        self.output = output
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
