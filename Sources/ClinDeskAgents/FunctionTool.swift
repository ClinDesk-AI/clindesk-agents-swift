import Foundation

public enum ToolTimeoutBehavior: String, Codable, Equatable, Sendable {
    case errorAsResult = "error_as_result"
    case raiseException = "raise_exception"
}

public typealias ToolErrorFunction<Context: Sendable> = @Sendable (
    RunContext<Context>,
    Error
) async throws -> String

public struct FunctionTool<Context: Sendable>: Sendable {
    public typealias Enabled = @Sendable (RunContext<Context>) async -> Bool
    public typealias Approval = @Sendable (ToolApprovalRequest<Context>) async throws -> Bool
    public typealias Executor = @Sendable (ToolContext<Context>, JSONValue) async throws -> ToolOutput

    public var descriptor: ToolDescriptor
    public var isEnabled: Enabled
    public var approval: Approval?
    public var inputGuardrails: [ToolInputGuardrail<Context>]
    public var outputGuardrails: [ToolOutputGuardrail<Context>]
    public var timeoutSeconds: TimeInterval?
    public var timeoutBehavior: ToolTimeoutBehavior
    public var timeoutErrorFunction: ToolErrorFunction<Context>?
    public var failureErrorFunction: ToolErrorFunction<Context>?
    var toolOrigin: ToolOrigin?
    var emitToolOrigin: Bool
    private let executor: Executor

    public init(
        name: String,
        description: String,
        parameters: JSONValue = .emptyObject,
        strict: Bool = true,
        deferLoading: Bool = false,
        failureErrorFunction: ToolErrorFunction<Context>? = FunctionTool.defaultFailureErrorFunction,
        isEnabled: @escaping Enabled = { _ in true },
        approval: Approval? = nil,
        inputGuardrails: [ToolInputGuardrail<Context>] = [],
        outputGuardrails: [ToolOutputGuardrail<Context>] = [],
        timeoutSeconds: TimeInterval? = nil,
        timeoutBehavior: ToolTimeoutBehavior = .errorAsResult,
        timeoutErrorFunction: ToolErrorFunction<Context>? = nil,
        toolOrigin: ToolOrigin? = nil,
        emitToolOrigin: Bool = true,
        execute: @escaping Executor
    ) {
        self.descriptor = ToolDescriptor(
            name: name,
            description: description,
            parameters: parameters,
            strict: strict,
            deferLoading: deferLoading
        )
        self.isEnabled = isEnabled
        self.approval = approval
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.timeoutSeconds = timeoutSeconds
        self.timeoutBehavior = timeoutBehavior
        self.timeoutErrorFunction = timeoutErrorFunction
        self.failureErrorFunction = failureErrorFunction
        self.toolOrigin = toolOrigin
        self.emitToolOrigin = emitToolOrigin
        self.executor = execute
    }

    public init<Input: Decodable & Sendable>(
        name: String,
        description: String,
        parameters: JSONValue,
        strict: Bool = true,
        deferLoading: Bool = false,
        failureErrorFunction: ToolErrorFunction<Context>? = FunctionTool.defaultFailureErrorFunction,
        isEnabled: @escaping Enabled = { _ in true },
        approval: Approval? = nil,
        inputGuardrails: [ToolInputGuardrail<Context>] = [],
        outputGuardrails: [ToolOutputGuardrail<Context>] = [],
        timeoutSeconds: TimeInterval? = nil,
        timeoutBehavior: ToolTimeoutBehavior = .errorAsResult,
        timeoutErrorFunction: ToolErrorFunction<Context>? = nil,
        toolOrigin: ToolOrigin? = nil,
        emitToolOrigin: Bool = true,
        decodeUsing decoder: JSONDecoder = JSONDecoder(),
        execute: @escaping @Sendable (ToolContext<Context>, Input) async throws -> ToolOutput
    ) {
        self.init(
            name: name,
            description: description,
            parameters: parameters,
            strict: strict,
            deferLoading: deferLoading,
            failureErrorFunction: failureErrorFunction,
            isEnabled: isEnabled,
            approval: approval,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            timeoutSeconds: timeoutSeconds,
            timeoutBehavior: timeoutBehavior,
            timeoutErrorFunction: timeoutErrorFunction,
            toolOrigin: toolOrigin,
            emitToolOrigin: emitToolOrigin
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

    public var resolvedToolOrigin: ToolOrigin? {
        guard emitToolOrigin else {
            return nil
        }
        return toolOrigin ?? ToolOrigin(type: .function)
    }

    public func run(_ context: ToolContext<Context>) async throws -> ToolOutput {
        do {
            let output = try await invoke(context)
            try output.validate()
            return output
        } catch let timeoutError as ToolTimeoutError {
            guard timeoutBehavior == .errorAsResult else {
                throw timeoutError
            }
            if let timeoutErrorFunction {
                return .text(try await timeoutErrorFunction(context.runContext, timeoutError))
            }
            return .text(ToolTimeoutError.defaultMessage(
                toolName: descriptor.name,
                timeoutSeconds: timeoutError.timeoutSeconds
            ))
        } catch let agentsError as AgentsError {
            if case .invalidRunConfig = agentsError {
                throw agentsError
            }
            guard let failureErrorFunction else {
                throw agentsError
            }
            return .text(try await failureErrorFunction(context.runContext, agentsError))
        } catch {
            guard let failureErrorFunction else {
                throw error
            }
            return .text(try await failureErrorFunction(context.runContext, error))
        }
    }

    public static func defaultFailureErrorFunction(
        _ context: RunContext<Context>,
        _ error: Error
    ) async throws -> String {
        let message = error.localizedDescription
        return "An error occurred while running the tool. Please try again. Error: \(message)"
    }

    private func invoke(_ context: ToolContext<Context>) async throws -> ToolOutput {
        guard let timeoutSeconds else {
            return try await executor(context, context.call.arguments)
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw AgentsError.invalidRunConfig("FunctionTool timeoutSeconds must be a positive finite number.")
        }
        let timeoutNanoseconds = UInt64((timeoutSeconds * 1_000_000_000).rounded(.up))

        return try await withThrowingTaskGroup(of: ToolOutput.self) { group in
            group.addTask {
                try await executor(context, context.call.arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw ToolTimeoutError(toolName: descriptor.name, timeoutSeconds: timeoutSeconds)
            }

            guard let result = try await group.next() else {
                throw AgentsError.invalidModelResponse("Function tool invocation produced no result.")
            }
            group.cancelAll()
            return result
        }
    }
}
