import Foundation

public final class RunResultStreaming<Context: Sendable>: @unchecked Sendable {
    private struct State {
        var currentAgent: Agent<Context>
        var currentTurn: Int
        var finalOutput: String?
        var trace: Trace?
        var isComplete: Bool
        var newItems: [ModelInputItem]
        var modelResponses: [ModelResponse]
        var usage: Usage
        var responseID: String?
        var inputGuardrailResults: [InputGuardrailResult]
        var outputGuardrailResults: [OutputGuardrailResult]
        var toolInputGuardrailResults: [ToolInputGuardrailResult]
        var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
        var interruptions: [ToolApprovalItem]
        var resumeState: RunState<Context>?
        var storedError: Error?
    }

    public let input: [ModelInputItem]
    public let maxTurns: Int?
    private let lock = NSLock()
    private var state: State
    private var stream: AsyncThrowingStream<RunStreamEvent<Context>, Error>?
    private var runTask: Task<Void, Never>?

    public init(input: [ModelInputItem], currentAgent: Agent<Context>, maxTurns: Int?) {
        self.input = input
        self.maxTurns = maxTurns
        self.state = State(
            currentAgent: currentAgent,
            currentTurn: 0,
            finalOutput: nil,
            trace: nil,
            isComplete: false,
            newItems: [],
            modelResponses: [],
            usage: Usage(),
            responseID: nil,
            inputGuardrailResults: [],
            outputGuardrailResults: [],
            toolInputGuardrailResults: [],
            toolOutputGuardrailResults: [],
            interruptions: [],
            resumeState: nil,
            storedError: nil
        )
    }

    public var currentAgent: Agent<Context> {
        locked { state.currentAgent }
    }

    public var currentTurn: Int {
        locked { state.currentTurn }
    }

    public var finalOutput: String? {
        locked { state.finalOutput }
    }

    public var trace: Trace? {
        locked { state.trace }
    }

    public var isComplete: Bool {
        locked { state.isComplete }
    }

    public var newItems: [ModelInputItem] {
        locked { state.newItems }
    }

    public var modelResponses: [ModelResponse] {
        locked { state.modelResponses }
    }

    public var usage: Usage {
        locked { state.usage }
    }

    public var responseID: String? {
        locked { state.responseID }
    }

    public var inputGuardrailResults: [InputGuardrailResult] {
        locked { state.inputGuardrailResults }
    }

    public var outputGuardrailResults: [OutputGuardrailResult] {
        locked { state.outputGuardrailResults }
    }

    public var toolInputGuardrailResults: [ToolInputGuardrailResult] {
        locked { state.toolInputGuardrailResults }
    }

    public var toolOutputGuardrailResults: [ToolOutputGuardrailResult] {
        locked { state.toolOutputGuardrailResults }
    }

    public var interruptions: [ToolApprovalItem] {
        locked { state.interruptions }
    }

    public var lastAgent: Agent<Context> {
        currentAgent
    }

    public var lastAgentName: String {
        currentAgent.name
    }

    public var lastResponseID: String? {
        locked { state.modelResponses.last?.responseID ?? state.responseID }
    }

    public var runLoopException: Error? {
        locked { state.storedError }
    }

    public func streamEvents() -> AsyncThrowingStream<RunStreamEvent<Context>, Error> {
        guard let stream else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
        return stream
    }

    public func cancel() {
        runTask?.cancel()
        lock.lock()
        state.isComplete = true
        lock.unlock()
    }

    public func toState(as type: Context.Type = Context.self) -> RunState<Context>? {
        locked { state.resumeState }
    }

    public func state(as type: Context.Type = Context.self) -> RunState<Context>? {
        toState(as: type)
    }

    func attach(
        stream: AsyncThrowingStream<RunStreamEvent<Context>, Error>,
        task: Task<Void, Never>?
    ) {
        lock.lock()
        self.stream = stream
        self.runTask = task
        lock.unlock()
    }

    func record(_ event: RunStreamEvent<Context>) {
        lock.lock()
        switch event {
        case .agentUpdatedStreamEvent(let event):
            state.currentAgent = event.newAgent
        case .modelResponseEvent(let event):
            if case .completed(let response) = event.data {
                state.currentTurn += 1
                state.modelResponses.append(response)
                state.responseID = response.responseID
            }
        case .runItemStreamEvent(let event):
            if let item = event.item.toInputItem() {
                state.newItems.append(item)
            }
        }
        lock.unlock()
    }

    func finish(_ result: RunResult) {
        lock.lock()
        state.finalOutput = result.isInterrupted ? nil : result.finalOutput
        state.trace = result.trace
        state.isComplete = true
        state.newItems = result.newItems
        state.modelResponses = result.modelResponses
        state.usage = result.usage
        state.responseID = result.responseID
        state.inputGuardrailResults = result.inputGuardrailResults
        state.outputGuardrailResults = result.outputGuardrailResults
        state.toolInputGuardrailResults = result.toolInputGuardrailResults
        state.toolOutputGuardrailResults = result.toolOutputGuardrailResults
        state.interruptions = result.interruptions
        state.resumeState = result.toState(as: Context.self)
        lock.unlock()
    }

    func recordInputGuardrailResult(_ result: InputGuardrailResult) {
        lock.lock()
        state.inputGuardrailResults.append(result)
        lock.unlock()
    }

    func fail(_ error: Error) {
        lock.lock()
        state.storedError = error
        state.isComplete = true
        lock.unlock()
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        let value = body()
        lock.unlock()
        return value
    }
}
