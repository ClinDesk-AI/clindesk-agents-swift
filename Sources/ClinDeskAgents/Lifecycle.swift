import Foundation

public struct RunHooks<Context: Sendable>: Sendable {
    public var onLLMStart: @Sendable (
        RunContext<Context>,
        Agent<Context>,
        String?,
        [ModelInputItem]
    ) async throws -> Void
    public var onLLMEnd: @Sendable (RunContext<Context>, Agent<Context>, ModelResponse) async throws -> Void
    public var onAgentStart: @Sendable (RunContext<Context>, Agent<Context>) async throws -> Void
    public var onAgentEnd: @Sendable (RunContext<Context>, Agent<Context>, String) async throws -> Void
    public var onHandoff: @Sendable (
        RunContext<Context>,
        Agent<Context>,
        Agent<Context>
    ) async throws -> Void
    public var onToolStart: @Sendable (
        ToolHookContext<Context>,
        Agent<Context>,
        Tool<Context>
    ) async throws -> Void
    public var onToolEnd: @Sendable (
        ToolHookContext<Context>,
        Agent<Context>,
        Tool<Context>,
        String
    ) async throws -> Void
    public var onGuardrail: @Sendable (String, GuardrailFunctionOutput) async throws -> Void

    public init(
        onLLMStart: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            String?,
            [ModelInputItem]
        ) async throws -> Void = { _, _, _, _ in },
        onLLMEnd: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            ModelResponse
        ) async throws -> Void = { _, _, _ in },
        onAgentStart: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>
        ) async throws -> Void = { _, _ in },
        onAgentEnd: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            String
        ) async throws -> Void = { _, _, _ in },
        onHandoff: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            Agent<Context>
        ) async throws -> Void = { _, _, _ in },
        onToolStart: @escaping @Sendable (
            ToolHookContext<Context>,
            Agent<Context>,
            Tool<Context>
        ) async throws -> Void = { _, _, _ in },
        onToolEnd: @escaping @Sendable (
            ToolHookContext<Context>,
            Agent<Context>,
            Tool<Context>,
            String
        ) async throws -> Void = { _, _, _, _ in },
        onGuardrail: @escaping @Sendable (
            String,
            GuardrailFunctionOutput
        ) async throws -> Void = { _, _ in }
    ) {
        self.onLLMStart = onLLMStart
        self.onLLMEnd = onLLMEnd
        self.onAgentStart = onAgentStart
        self.onAgentEnd = onAgentEnd
        self.onHandoff = onHandoff
        self.onToolStart = onToolStart
        self.onToolEnd = onToolEnd
        self.onGuardrail = onGuardrail
    }
}

public struct AgentHooks<Context: Sendable>: Sendable {
    public var onStart: @Sendable (RunContext<Context>, Agent<Context>) async throws -> Void
    public var onEnd: @Sendable (RunContext<Context>, Agent<Context>, String) async throws -> Void
    public var onHandoff: @Sendable (
        RunContext<Context>,
        Agent<Context>,
        Agent<Context>
    ) async throws -> Void
    public var onToolStart: @Sendable (
        ToolHookContext<Context>,
        Agent<Context>,
        Tool<Context>
    ) async throws -> Void
    public var onToolEnd: @Sendable (
        ToolHookContext<Context>,
        Agent<Context>,
        Tool<Context>,
        String
    ) async throws -> Void
    public var onLLMStart: @Sendable (
        RunContext<Context>,
        Agent<Context>,
        String?,
        [ModelInputItem]
    ) async throws -> Void
    public var onLLMEnd: @Sendable (RunContext<Context>, Agent<Context>, ModelResponse) async throws -> Void

    public init(
        onStart: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>
        ) async throws -> Void = { _, _ in },
        onEnd: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            String
        ) async throws -> Void = { _, _, _ in },
        onHandoff: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            Agent<Context>
        ) async throws -> Void = { _, _, _ in },
        onToolStart: @escaping @Sendable (
            ToolHookContext<Context>,
            Agent<Context>,
            Tool<Context>
        ) async throws -> Void = { _, _, _ in },
        onToolEnd: @escaping @Sendable (
            ToolHookContext<Context>,
            Agent<Context>,
            Tool<Context>,
            String
        ) async throws -> Void = { _, _, _, _ in },
        onLLMStart: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            String?,
            [ModelInputItem]
        ) async throws -> Void = { _, _, _, _ in },
        onLLMEnd: @escaping @Sendable (
            RunContext<Context>,
            Agent<Context>,
            ModelResponse
        ) async throws -> Void = { _, _, _ in }
    ) {
        self.onStart = onStart
        self.onEnd = onEnd
        self.onHandoff = onHandoff
        self.onToolStart = onToolStart
        self.onToolEnd = onToolEnd
        self.onLLMStart = onLLMStart
        self.onLLMEnd = onLLMEnd
    }
}
