import Foundation

public struct ToolDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    public var strict: Bool

    public init(
        name: String,
        description: String,
        parameters: JSONValue = .emptyObject,
        strict: Bool = true
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public enum ToolOutput: Equatable, Sendable {
    case text(String)
    case json(JSONValue)

    public var modelValue: JSONValue {
        switch self {
        case .text(let text):
            return .string(text)
        case .json(let value):
            return value
        }
    }

    public var finalOutputText: String {
        switch self {
        case .text(let text):
            return text
        case .json(let value):
            return value.prettyPrinted()
        }
    }
}

public struct ToolContext<Context: Sendable>: Sendable {
    public var runContext: RunContext<Context>
    public var call: FunctionCall

    public init(runContext: RunContext<Context>, call: FunctionCall) {
        self.runContext = runContext
        self.call = call
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

public struct FunctionTool<Context: Sendable>: Sendable {
    public typealias Enabled = @Sendable (RunContext<Context>) async -> Bool
    public typealias Approval = @Sendable (ToolApprovalRequest<Context>) async throws -> Bool
    public typealias Executor = @Sendable (ToolContext<Context>, JSONValue) async throws -> ToolOutput

    public var descriptor: ToolDescriptor
    public var isEnabled: Enabled
    public var approval: Approval?
    public var inputGuardrails: [ToolInputGuardrail<Context>]
    public var outputGuardrails: [ToolOutputGuardrail<Context>]
    private let executor: Executor

    public init(
        name: String,
        description: String,
        parameters: JSONValue = .emptyObject,
        strict: Bool = true,
        isEnabled: @escaping Enabled = { _ in true },
        approval: Approval? = nil,
        inputGuardrails: [ToolInputGuardrail<Context>] = [],
        outputGuardrails: [ToolOutputGuardrail<Context>] = [],
        execute: @escaping Executor
    ) {
        self.descriptor = ToolDescriptor(
            name: name,
            description: description,
            parameters: parameters,
            strict: strict
        )
        self.isEnabled = isEnabled
        self.approval = approval
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.executor = execute
    }

    public init<Input: Decodable & Sendable>(
        name: String,
        description: String,
        parameters: JSONValue,
        strict: Bool = true,
        isEnabled: @escaping Enabled = { _ in true },
        approval: Approval? = nil,
        inputGuardrails: [ToolInputGuardrail<Context>] = [],
        outputGuardrails: [ToolOutputGuardrail<Context>] = [],
        decodeUsing decoder: JSONDecoder = JSONDecoder(),
        execute: @escaping @Sendable (ToolContext<Context>, Input) async throws -> ToolOutput
    ) {
        self.init(
            name: name,
            description: description,
            parameters: parameters,
            strict: strict,
            isEnabled: isEnabled,
            approval: approval,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails
        ) { context, json in
            guard case .object = json else {
                throw AgentsError.invalidToolArguments(
                    toolName: name,
                    reason: "Function tool input must be a JSON object."
                )
            }
            do {
                let input = try json.decoded(Input.self, using: decoder)
                return try await execute(context, input)
            } catch {
                throw AgentsError.invalidToolArguments(toolName: name, reason: error.localizedDescription)
            }
        }
    }

    public func run(_ context: ToolContext<Context>) async throws -> ToolOutput {
        try await executor(context, context.call.arguments)
    }
}

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

    public init(call: FunctionCall, output: ToolOutput) {
        self.call = call
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
