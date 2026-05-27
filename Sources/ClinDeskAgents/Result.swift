import Foundation

public enum ToInputListMode: String, Sendable {
    case preserveAll = "preserve_all"
    case normalized
}

public struct AgentToolInvocation: Equatable, Sendable {
    public var toolName: String
    public var toolCallID: String
    public var toolArguments: JSONValue

    public init(toolName: String, toolCallID: String, toolArguments: JSONValue) {
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.toolArguments = toolArguments
    }
}

public struct AgentSnapshot: Equatable, Sendable {
    public var name: String
    public var handoffDescription: String?
    public var modelName: String?

    public init(name: String, handoffDescription: String? = nil, modelName: String? = nil) {
        self.name = name
        self.handoffDescription = handoffDescription
        self.modelName = modelName
    }

    public init<Context: Sendable>(_ agent: Agent<Context>) {
        self.init(
            name: agent.name,
            handoffDescription: agent.handoffDescription,
            modelName: agent.modelName
        )
    }
}

public struct RunResult: Sendable {
    public var input: [ModelInputItem]
    public var finalOutput: String
    public var lastAgent: AgentSnapshot
    public var lastAgentName: String
    public var trace: Trace
    public var newItems: [ModelInputItem]
    public var modelResponses: [ModelResponse]
    public var usage: Usage
    public var responseID: String?
    public var inputGuardrailResults: [InputGuardrailResult]
    public var outputGuardrailResults: [OutputGuardrailResult]
    public var toolInputGuardrailResults: [ToolInputGuardrailResult]
    public var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    public var interruptions: [ToolApprovalItem]
    public var resumeState: (any AnyRunState)?
    public var agentToolInvocation: AgentToolInvocation?
    var modelInputItems: [ModelInputItem]
    var replayFromModelInputItems: Bool

    public init(
        input: [ModelInputItem],
        finalOutput: String,
        lastAgentName: String,
        lastAgent: AgentSnapshot? = nil,
        trace: Trace,
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse] = [],
        usage: Usage = Usage(),
        responseID: String? = nil,
        inputGuardrailResults: [InputGuardrailResult] = [],
        outputGuardrailResults: [OutputGuardrailResult] = [],
        toolInputGuardrailResults: [ToolInputGuardrailResult] = [],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult] = [],
        interruptions: [ToolApprovalItem] = [],
        resumeState: (any AnyRunState)? = nil,
        agentToolInvocation: AgentToolInvocation? = nil,
        modelInputItems: [ModelInputItem]? = nil,
        replayFromModelInputItems: Bool = false
    ) {
        self.input = input
        self.finalOutput = finalOutput
        self.lastAgentName = lastAgentName
        self.lastAgent = lastAgent ?? AgentSnapshot(name: lastAgentName)
        self.trace = trace
        self.newItems = newItems
        self.modelResponses = modelResponses
        self.usage = usage
        self.responseID = responseID
        self.inputGuardrailResults = inputGuardrailResults
        self.outputGuardrailResults = outputGuardrailResults
        self.toolInputGuardrailResults = toolInputGuardrailResults
        self.toolOutputGuardrailResults = toolOutputGuardrailResults
        self.interruptions = interruptions
        self.resumeState = resumeState
        self.agentToolInvocation = agentToolInvocation
        self.modelInputItems = modelInputItems ?? newItems
        self.replayFromModelInputItems = replayFromModelInputItems
    }

    public func toInputList(mode: ToInputListMode = .preserveAll) -> [ModelInputItem] {
        switch mode {
        case .preserveAll:
            return input + newItems
        case .normalized:
            return input + (replayFromModelInputItems ? modelInputItems : newItems)
        }
    }

    public var lastResponseID: String? {
        modelResponses.last?.responseID ?? responseID
    }

    public var isInterrupted: Bool {
        !interruptions.isEmpty
    }

    public func finalOutput<Output: Decodable>(
        as outputType: Output.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        try StructuredOutput.decode(outputType, from: finalOutput, decoder: decoder)
    }

    public func finalOutputAs<Output: Decodable>(
        _ outputType: Output.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        try finalOutput(as: outputType, decoder: decoder)
    }

    public func toState<Context: Sendable>(as type: Context.Type = Context.self) -> RunState<Context>? {
        resumeState as? RunState<Context>
    }

    public func state<Context: Sendable>(as type: Context.Type = Context.self) -> RunState<Context>? {
        toState(as: type)
    }
}

extension RunResult: CustomStringConvertible {
    public var description: String {
        prettyPrintResult(self)
    }
}

extension RunResult: Equatable {
    public static func == (lhs: RunResult, rhs: RunResult) -> Bool {
        lhs.input == rhs.input
            && lhs.finalOutput == rhs.finalOutput
            && lhs.lastAgent == rhs.lastAgent
            && lhs.lastAgentName == rhs.lastAgentName
            && lhs.trace == rhs.trace
            && lhs.newItems == rhs.newItems
            && lhs.modelResponses == rhs.modelResponses
            && lhs.usage == rhs.usage
            && lhs.responseID == rhs.responseID
            && lhs.inputGuardrailResults == rhs.inputGuardrailResults
            && lhs.outputGuardrailResults == rhs.outputGuardrailResults
            && lhs.toolInputGuardrailResults == rhs.toolInputGuardrailResults
            && lhs.toolOutputGuardrailResults == rhs.toolOutputGuardrailResults
            && lhs.interruptions == rhs.interruptions
            && lhs.agentToolInvocation == rhs.agentToolInvocation
    }
}

public struct TypedRunResult<Output: Sendable>: Sendable {
    public var input: [ModelInputItem]
    public var finalOutput: Output
    public var rawFinalOutput: String
    public var lastAgent: AgentSnapshot
    public var lastAgentName: String
    public var trace: Trace
    public var newItems: [ModelInputItem]
    public var modelResponses: [ModelResponse]
    public var usage: Usage
    public var responseID: String?
    public var inputGuardrailResults: [InputGuardrailResult]
    public var outputGuardrailResults: [OutputGuardrailResult]
    public var toolInputGuardrailResults: [ToolInputGuardrailResult]
    public var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    public var interruptions: [ToolApprovalItem]
    public var agentToolInvocation: AgentToolInvocation?
    var modelInputItems: [ModelInputItem]
    var replayFromModelInputItems: Bool

    public init(
        input: [ModelInputItem],
        finalOutput: Output,
        rawFinalOutput: String,
        lastAgentName: String,
        lastAgent: AgentSnapshot? = nil,
        trace: Trace,
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse] = [],
        usage: Usage = Usage(),
        responseID: String? = nil,
        inputGuardrailResults: [InputGuardrailResult] = [],
        outputGuardrailResults: [OutputGuardrailResult] = [],
        toolInputGuardrailResults: [ToolInputGuardrailResult] = [],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult] = [],
        interruptions: [ToolApprovalItem] = [],
        agentToolInvocation: AgentToolInvocation? = nil,
        modelInputItems: [ModelInputItem]? = nil,
        replayFromModelInputItems: Bool = false
    ) {
        self.input = input
        self.finalOutput = finalOutput
        self.rawFinalOutput = rawFinalOutput
        self.lastAgentName = lastAgentName
        self.lastAgent = lastAgent ?? AgentSnapshot(name: lastAgentName)
        self.trace = trace
        self.newItems = newItems
        self.modelResponses = modelResponses
        self.usage = usage
        self.responseID = responseID
        self.inputGuardrailResults = inputGuardrailResults
        self.outputGuardrailResults = outputGuardrailResults
        self.toolInputGuardrailResults = toolInputGuardrailResults
        self.toolOutputGuardrailResults = toolOutputGuardrailResults
        self.interruptions = interruptions
        self.agentToolInvocation = agentToolInvocation
        self.modelInputItems = modelInputItems ?? newItems
        self.replayFromModelInputItems = replayFromModelInputItems
    }

    public func toInputList(mode: ToInputListMode = .preserveAll) -> [ModelInputItem] {
        switch mode {
        case .preserveAll:
            return input + newItems
        case .normalized:
            return input + (replayFromModelInputItems ? modelInputItems : newItems)
        }
    }

    public var lastResponseID: String? {
        modelResponses.last?.responseID ?? responseID
    }
}
