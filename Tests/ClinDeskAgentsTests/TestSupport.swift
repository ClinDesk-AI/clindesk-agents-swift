#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import ClinDeskAgents

struct CapturedModelRequest: Equatable, Sendable {
    var instructions: String?
    var prompt: Prompt?
    var input: [ModelInputItem]
    var tools: [ModelTool]
    var handoffs: [HandoffDescriptor]
    var outputSchema: AgentOutputSchema?
    var tracing: ModelTracing
    var settings: ModelSettings
    var maxOutputTokens: Int?

    init<Context: Sendable>(_ request: ModelRequest<Context>) {
        self.instructions = request.instructions
        self.prompt = request.prompt
        self.input = request.input
        self.tools = request.tools
        self.handoffs = request.handoffs
        self.outputSchema = request.outputSchema
        self.tracing = request.tracing
        self.settings = request.settings
        self.maxOutputTokens = request.settings.maxOutputTokens
    }
}

struct StructuredAnswer: Decodable, Equatable, Sendable {
    let answer: String
}

actor FakeModelStore {
    var responses: [ModelResponse]
    var capturedRequests: [CapturedModelRequest] = []

    init(_ responses: [ModelResponse]) {
        self.responses = responses
    }

    func next<Context: Sendable>(for request: ModelRequest<Context>) throws -> ModelResponse {
        capturedRequests.append(CapturedModelRequest(request))
        guard !responses.isEmpty else {
            throw AgentsError.invalidModelResponse("No fake response queued.")
        }
        return responses.removeFirst()
    }

    func requests() -> [CapturedModelRequest] {
        capturedRequests
    }
}

actor ConcurrencyTracker {
    private var active = 0
    private var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }

    func maxObserved() -> Int {
        maximum
    }
}

struct FakeModel: Model {
    let store: FakeModelStore

    init(_ responses: [ModelResponse]) {
        self.store = FakeModelStore(responses)
    }

    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        try await store.next(for: request)
    }

    func requests() async -> [CapturedModelRequest] {
        await store.requests()
    }
}

actor FlakyModelStore {
    private var failuresRemaining: Int
    private let error: any Error
    private let response: ModelResponse
    private var capturedRequests: [CapturedModelRequest] = []

    init(failures: Int, error: any Error, response: ModelResponse) {
        self.failuresRemaining = failures
        self.error = error
        self.response = response
    }

    func next<Context: Sendable>(for request: ModelRequest<Context>) throws -> ModelResponse {
        capturedRequests.append(CapturedModelRequest(request))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw error
        }
        return response
    }

    func requests() -> [CapturedModelRequest] {
        capturedRequests
    }
}

struct FlakyModel: Model {
    let store: FlakyModelStore
    let advice: ModelRetryAdvice?

    init(failures: Int, error: any Error, response: ModelResponse, advice: ModelRetryAdvice? = nil) {
        self.store = FlakyModelStore(failures: failures, error: error, response: response)
        self.advice = advice
    }

    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        try await store.next(for: request)
    }

    func retryAdvice(for request: ModelRetryAdviceRequest) -> ModelRetryAdvice? {
        advice
    }

    func requests() async -> [CapturedModelRequest] {
        await store.requests()
    }
}

actor RequestCapture {
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        self.request = request
    }

    func get() -> URLRequest? {
        request
    }
}

actor StringRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func all() -> [String] {
        values
    }
}

extension ModelResponse {
    var finalText: String {
        outputText
    }
}

extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let values) = self {
            return values
        }
        return nil
    }
}
