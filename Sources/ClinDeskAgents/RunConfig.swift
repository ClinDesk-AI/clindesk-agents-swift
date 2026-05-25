import Foundation

public enum ToolNotFoundBehavior: Sendable {
    case throwError
    case returnErrorToModel
}

public struct ToolExecutionConfig: Equatable, Sendable {
    public var maxFunctionToolConcurrency: Int?

    public init(maxFunctionToolConcurrency: Int? = nil) {
        self.maxFunctionToolConcurrency = maxFunctionToolConcurrency
    }
}

public struct RunConfig<Context: Sendable>: Sendable {
    public var model: (any Model)?
    public var modelName: String?
    public var modelSettings: ModelSettings?
    public var maxTurns: Int
    public var workflowName: String
    public var traceID: String?
    public var groupID: String?
    public var traceMetadata: [String: String]
    public var traceIncludeSensitiveData: Bool
    public var tracingProcessors: [any TracingProcessor]
    public var hooks: RunHooks<Context>
    public var session: (any Session)?
    public var previousResponseID: String?
    public var conversationID: String?
    public var toolNotFoundBehavior: ToolNotFoundBehavior
    public var toolExecution: ToolExecutionConfig

    public init(
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings? = nil,
        maxTurns: Int = 10,
        workflowName: String = "Agent workflow",
        traceID: String? = nil,
        groupID: String? = nil,
        traceMetadata: [String: String] = [:],
        traceIncludeSensitiveData: Bool = false,
        tracingProcessors: [any TracingProcessor] = [],
        hooks: RunHooks<Context> = RunHooks(),
        session: (any Session)? = nil,
        previousResponseID: String? = nil,
        conversationID: String? = nil,
        toolNotFoundBehavior: ToolNotFoundBehavior = .throwError,
        toolExecution: ToolExecutionConfig = ToolExecutionConfig()
    ) {
        self.model = model
        self.modelName = modelName
        self.modelSettings = modelSettings
        self.maxTurns = maxTurns
        self.workflowName = workflowName
        self.traceID = traceID
        self.groupID = groupID
        self.traceMetadata = traceMetadata
        self.traceIncludeSensitiveData = traceIncludeSensitiveData
        self.tracingProcessors = tracingProcessors
        self.hooks = hooks
        self.session = session
        self.previousResponseID = previousResponseID
        self.conversationID = conversationID
        self.toolNotFoundBehavior = toolNotFoundBehavior
        self.toolExecution = toolExecution
    }
}

public struct RunResult: Equatable, Sendable {
    public var finalOutput: String
    public var lastAgentName: String
    public var trace: Trace
    public var newItems: [ModelInputItem]
    public var responseID: String?

    public init(
        finalOutput: String,
        lastAgentName: String,
        trace: Trace,
        newItems: [ModelInputItem],
        responseID: String? = nil
    ) {
        self.finalOutput = finalOutput
        self.lastAgentName = lastAgentName
        self.trace = trace
        self.newItems = newItems
        self.responseID = responseID
    }
}
