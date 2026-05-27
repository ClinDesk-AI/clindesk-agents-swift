import Foundation

public enum ModelTracing: Equatable, Sendable {
    case disabled
    case enabled(includeData: Bool)
}

public struct ModelRequest<Context: Sendable>: Sendable {
    public var instructions: String?
    public var prompt: Prompt?
    public var input: [ModelInputItem]
    public var context: RunContext<Context>
    public var settings: ModelSettings
    public var tools: [ModelTool]
    public var handoffs: [HandoffDescriptor]
    public var outputSchema: AgentOutputSchema?
    public var tracing: ModelTracing

    public init(
        instructions: String?,
        prompt: Prompt? = nil,
        input: [ModelInputItem],
        context: RunContext<Context>,
        settings: ModelSettings,
        tools: [ModelTool],
        handoffs: [HandoffDescriptor],
        outputSchema: AgentOutputSchema? = nil,
        tracing: ModelTracing = .enabled(includeData: false)
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.input = input
        self.context = context
        self.settings = settings
        self.tools = tools
        self.handoffs = handoffs
        self.outputSchema = outputSchema
        self.tracing = tracing
    }
}

public protocol Model: Sendable {
    var supportsDefaultPromptCacheKey: Bool { get }
    func close() async
    func retryAdvice(for request: ModelRetryAdviceRequest) -> ModelRetryAdvice?
    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse
    func streamResponse<Context: Sendable>(_ request: ModelRequest<Context>) -> AsyncThrowingStream<ModelStreamEvent, Error>
}

public extension Model {
    var supportsDefaultPromptCacheKey: Bool {
        false
    }

    func close() async {}

    func retryAdvice(for request: ModelRetryAdviceRequest) -> ModelRetryAdvice? {
        nil
    }

    func streamResponse<Context: Sendable>(_ request: ModelRequest<Context>) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.started)
                    let response = try await getResponse(request)
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public enum ModelStreamEvent: Equatable, Sendable {
    case started
    case outputDelta(String)
    case toolCallDelta(FunctionCall)
    case completed(ModelResponse)
}

public protocol ModelProvider: Sendable {
    func model(named name: String?) async throws -> any Model
    func close() async
}

public extension ModelProvider {
    func close() async {}
}

public struct StaticModelProvider: ModelProvider {
    private let defaultModel: any Model
    private let namedModels: [String: any Model]

    public init(defaultModel: any Model, namedModels: [String: any Model] = [:]) {
        self.defaultModel = defaultModel
        self.namedModels = namedModels
    }

    public func model(named name: String?) async throws -> any Model {
        guard let name else {
            return defaultModel
        }
        guard let model = namedModels[name] else {
            throw AgentsError.modelNotFound(name)
        }
        return model
    }
}
