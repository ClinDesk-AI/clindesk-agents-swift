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

public typealias HandoffInputFilter = @Sendable ([ModelInputItem]) async throws -> [ModelInputItem]
public typealias SessionInputCallback = @Sendable (
    _ history: [ModelInputItem],
    _ newInput: [ModelInputItem]
) async throws -> [ModelInputItem]
public typealias CallModelInputFilter<Context: Sendable> = @Sendable (
    CallModelData<Context>
) async throws -> ModelInputData

public struct ModelInputData: Equatable, Sendable {
    public var input: [ModelInputItem]
    public var instructions: String?

    public init(input: [ModelInputItem], instructions: String?) {
        self.input = input
        self.instructions = instructions
    }
}

public struct CallModelData<Context: Sendable>: Sendable {
    public var modelData: ModelInputData
    public var agent: Agent<Context>
    public var context: Context?

    public init(modelData: ModelInputData, agent: Agent<Context>, context: Context?) {
        self.modelData = modelData
        self.agent = agent
        self.context = context
    }
}

public struct RunConfig<Context: Sendable>: Sendable {
    public var model: (any Model)?
    public var modelName: String?
    public var modelSettings: ModelSettings?
    public var handoffInputFilter: HandoffInputFilter?
    public var maxTurns: Int?
    public var workflowName: String
    public var traceID: String?
    public var groupID: String?
    public var traceMetadata: [String: String]
    public var traceIncludeSensitiveData: Bool
    public var tracingDisabled: Bool
    public var tracingProcessors: [any TracingProcessor]
    public var hooks: RunHooks<Context>
    public var session: (any Session)?
    public var sessionInputCallback: SessionInputCallback?
    public var callModelInputFilter: CallModelInputFilter<Context>?
    public var previousResponseID: String?
    public var autoPreviousResponseID: Bool
    public var conversationID: String?
    public var inputGuardrails: [InputGuardrail<Context>]
    public var outputGuardrails: [OutputGuardrail<Context>]
    public var toolNotFoundBehavior: ToolNotFoundBehavior
    public var toolExecution: ToolExecutionConfig

    public init(
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings? = nil,
        handoffInputFilter: HandoffInputFilter? = nil,
        maxTurns: Int? = 10,
        workflowName: String = "Agent workflow",
        traceID: String? = nil,
        groupID: String? = nil,
        traceMetadata: [String: String] = [:],
        traceIncludeSensitiveData: Bool = false,
        tracingDisabled: Bool = false,
        tracingProcessors: [any TracingProcessor] = [],
        hooks: RunHooks<Context> = RunHooks(),
        session: (any Session)? = nil,
        sessionInputCallback: SessionInputCallback? = nil,
        callModelInputFilter: CallModelInputFilter<Context>? = nil,
        previousResponseID: String? = nil,
        autoPreviousResponseID: Bool = false,
        conversationID: String? = nil,
        inputGuardrails: [InputGuardrail<Context>] = [],
        outputGuardrails: [OutputGuardrail<Context>] = [],
        toolNotFoundBehavior: ToolNotFoundBehavior = .throwError,
        toolExecution: ToolExecutionConfig = ToolExecutionConfig()
    ) {
        self.model = model
        self.modelName = modelName
        self.modelSettings = modelSettings
        self.handoffInputFilter = handoffInputFilter
        self.maxTurns = maxTurns
        self.workflowName = workflowName
        self.traceID = traceID
        self.groupID = groupID
        self.traceMetadata = traceMetadata
        self.traceIncludeSensitiveData = traceIncludeSensitiveData
        self.tracingDisabled = tracingDisabled
        self.tracingProcessors = tracingProcessors
        self.hooks = hooks
        self.session = session
        self.sessionInputCallback = sessionInputCallback
        self.callModelInputFilter = callModelInputFilter
        self.previousResponseID = previousResponseID
        self.autoPreviousResponseID = autoPreviousResponseID
        self.conversationID = conversationID
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
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
