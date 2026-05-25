import Foundation

public enum RunItem: Equatable, Sendable {
    case agentStarted(String)
    case modelRequest(String)
    case modelResponse(ModelResponse)
    case toolCall(FunctionCall)
    case toolResult(FunctionCallOutput)
    case handoff(String)
    case guardrail(String)
    case finalOutput(String)
}

public struct Trace: Equatable, Sendable {
    public var id: String
    public var workflowName: String
    public var groupID: String?
    public var metadata: [String: String]
    public var includeSensitiveData: Bool
    public var startedAt: Date
    public var endedAt: Date?
    public var items: [RunItem]

    public init(
        id: String = UUID().uuidString,
        workflowName: String = "Agent workflow",
        groupID: String? = nil,
        metadata: [String: String] = [:],
        includeSensitiveData: Bool = false,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        items: [RunItem] = []
    ) {
        self.id = id
        self.workflowName = workflowName
        self.groupID = groupID
        self.metadata = metadata
        self.includeSensitiveData = includeSensitiveData
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.items = items
    }
}

public protocol TracingProcessor: Sendable {
    func process(_ trace: Trace) async
}

public actor InMemoryTracingProcessor: TracingProcessor {
    private var traces: [Trace] = []

    public init() {}

    public func process(_ trace: Trace) async {
        traces.append(trace)
    }

    public func allTraces() -> [Trace] {
        traces
    }
}

public struct RunHooks<Context: Sendable>: Sendable {
    public var onAgentStart: @Sendable (Agent<Context>) -> Void
    public var onModelStart: @Sendable (Agent<Context>) -> Void
    public var onModelEnd: @Sendable (ModelResponse) -> Void
    public var onToolStart: @Sendable (FunctionTool<Context>, FunctionCall) -> Void
    public var onToolEnd: @Sendable (FunctionCallOutput) -> Void
    public var onHandoff: @Sendable (Handoff<Context>) -> Void
    public var onGuardrail: @Sendable (String, GuardrailFunctionOutput) -> Void
    public var onFinalOutput: @Sendable (String) -> Void

    public init(
        onAgentStart: @escaping @Sendable (Agent<Context>) -> Void = { _ in },
        onModelStart: @escaping @Sendable (Agent<Context>) -> Void = { _ in },
        onModelEnd: @escaping @Sendable (ModelResponse) -> Void = { _ in },
        onToolStart: @escaping @Sendable (FunctionTool<Context>, FunctionCall) -> Void = { _, _ in },
        onToolEnd: @escaping @Sendable (FunctionCallOutput) -> Void = { _ in },
        onHandoff: @escaping @Sendable (Handoff<Context>) -> Void = { _ in },
        onGuardrail: @escaping @Sendable (String, GuardrailFunctionOutput) -> Void = { _, _ in },
        onFinalOutput: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.onAgentStart = onAgentStart
        self.onModelStart = onModelStart
        self.onModelEnd = onModelEnd
        self.onToolStart = onToolStart
        self.onToolEnd = onToolEnd
        self.onHandoff = onHandoff
        self.onGuardrail = onGuardrail
        self.onFinalOutput = onFinalOutput
    }
}

public enum RunStreamEvent<Context: Sendable>: Sendable {
    case agentStarted(Agent<Context>)
    case modelStarted(Agent<Context>)
    case modelCompleted(ModelResponse)
    case toolStarted(FunctionTool<Context>, FunctionCall)
    case toolCompleted(FunctionCallOutput)
    case handoff(Handoff<Context>)
    case guardrail(String, GuardrailFunctionOutput)
    case finalOutput(String)
}
