import Foundation

public struct RunErrorData<Context: Sendable>: Sendable {
    public var input: [ModelInputItem]
    public var newItems: [ModelInputItem]
    public var history: [ModelInputItem]
    public var output: [ModelInputItem]
    public var modelResponses: [ModelResponse]
    public var lastAgent: Agent<Context>
    public var inputGuardrailResults: [InputGuardrailResult]
    public var outputGuardrailResults: [OutputGuardrailResult]

    public init(
        input: [ModelInputItem],
        newItems: [ModelInputItem],
        history: [ModelInputItem],
        output: [ModelInputItem],
        modelResponses: [ModelResponse],
        lastAgent: Agent<Context>,
        inputGuardrailResults: [InputGuardrailResult] = [],
        outputGuardrailResults: [OutputGuardrailResult] = []
    ) {
        self.input = input
        self.newItems = newItems
        self.history = history
        self.output = output
        self.modelResponses = modelResponses
        self.lastAgent = lastAgent
        self.inputGuardrailResults = inputGuardrailResults
        self.outputGuardrailResults = outputGuardrailResults
    }
}

public typealias RunErrorDetails<Context: Sendable> = RunErrorData<Context>

public struct RunErrorHandlerInput<Context: Sendable>: Sendable {
    public var error: AgentsError
    public var context: RunContext<Context>
    public var runData: RunErrorData<Context>

    public init(
        error: AgentsError,
        context: RunContext<Context>,
        runData: RunErrorData<Context>
    ) {
        self.error = error
        self.context = context
        self.runData = runData
    }
}

public struct RunErrorHandlerResult: Equatable, Sendable {
    public var finalOutput: String
    public var includeInHistory: Bool

    public init(finalOutput: String, includeInHistory: Bool = true) {
        self.finalOutput = finalOutput
        self.includeInHistory = includeInHistory
    }
}

public typealias RunErrorHandler<Context: Sendable> = @Sendable (
    RunErrorHandlerInput<Context>
) async throws -> RunErrorHandlerResult?

public struct RunErrorHandlers<Context: Sendable>: Sendable {
    public var maxTurns: RunErrorHandler<Context>?
    public var modelRefusal: RunErrorHandler<Context>?

    public init(
        maxTurns: RunErrorHandler<Context>? = nil,
        modelRefusal: RunErrorHandler<Context>? = nil
    ) {
        self.maxTurns = maxTurns
        self.modelRefusal = modelRefusal
    }
}
