import Foundation

public struct ModelSettings: Codable, Equatable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var parallelToolCalls: Bool?
    public var store: Bool?
    public var metadata: [String: String]

    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        parallelToolCalls: Bool? = nil,
        store: Bool? = nil,
        metadata: [String: String] = [:]
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.parallelToolCalls = parallelToolCalls
        self.store = store
        self.metadata = metadata
    }

    public func merging(_ override: ModelSettings?) -> ModelSettings {
        guard let override else {
            return self
        }
        return ModelSettings(
            temperature: override.temperature ?? temperature,
            topP: override.topP ?? topP,
            maxOutputTokens: override.maxOutputTokens ?? maxOutputTokens,
            parallelToolCalls: override.parallelToolCalls ?? parallelToolCalls,
            store: override.store ?? store,
            metadata: metadata.merging(override.metadata) { _, new in new }
        )
    }
}

public enum ModelTracing: Equatable, Sendable {
    case disabled
    case enabled(includeData: Bool)
}

public struct ModelRequest<Context: Sendable>: Sendable {
    public var instructions: String?
    public var input: [ModelInputItem]
    public var context: RunContext<Context>
    public var settings: ModelSettings
    public var tools: [ToolDescriptor]
    public var handoffs: [HandoffDescriptor]
    public var outputSchema: JSONValue?
    public var previousResponseID: String?
    public var conversationID: String?
    public var tracing: ModelTracing

    public init(
        instructions: String?,
        input: [ModelInputItem],
        context: RunContext<Context>,
        settings: ModelSettings,
        tools: [ToolDescriptor],
        handoffs: [HandoffDescriptor],
        outputSchema: JSONValue? = nil,
        previousResponseID: String? = nil,
        conversationID: String? = nil,
        tracing: ModelTracing = .enabled(includeData: false)
    ) {
        self.instructions = instructions
        self.input = input
        self.context = context
        self.settings = settings
        self.tools = tools
        self.handoffs = handoffs
        self.outputSchema = outputSchema
        self.previousResponseID = previousResponseID
        self.conversationID = conversationID
        self.tracing = tracing
    }
}

public protocol Model: Sendable {
    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse
    func streamResponse<Context: Sendable>(_ request: ModelRequest<Context>) -> AsyncThrowingStream<ModelStreamEvent, Error>
}

public extension Model {
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
