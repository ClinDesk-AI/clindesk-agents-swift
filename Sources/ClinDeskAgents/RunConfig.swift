import Foundation

public enum ToolNotFoundBehavior: String, Codable, Equatable, Sendable {
    case raiseError = "raise_error"
    case returnErrorToModel = "return_error_to_model"
}

public enum ReasoningItemIDPolicy: String, Codable, Equatable, Sendable {
    case preserve
    case omit
}

public struct ToolErrorFormatterArgs<Context: Sendable>: Sendable {
    public enum Kind: String, Sendable {
        case approvalRejected = "approval_rejected"
        case toolNotFound = "tool_not_found"
    }

    public enum ToolType: String, Sendable {
        case function
        case computer
        case shell
        case applyPatch = "apply_patch"
        case custom
    }

    public var kind: Kind
    public var toolType: ToolType
    public var toolName: String
    public var callID: String
    public var defaultMessage: String
    public var runContext: RunContext<Context>

    public init(
        kind: Kind,
        toolType: ToolType,
        toolName: String,
        callID: String,
        defaultMessage: String,
        runContext: RunContext<Context>
    ) {
        self.kind = kind
        self.toolType = toolType
        self.toolName = toolName
        self.callID = callID
        self.defaultMessage = defaultMessage
        self.runContext = runContext
    }
}

public typealias ToolErrorFormatter<Context: Sendable> = @Sendable (
    ToolErrorFormatterArgs<Context>
) async throws -> String?

public struct ToolExecutionConfig: Equatable, Sendable {
    public var maxFunctionToolConcurrency: Int?

    public init(maxFunctionToolConcurrency: Int? = nil) {
        self.maxFunctionToolConcurrency = maxFunctionToolConcurrency
    }
}

public enum RunConfigDefaults {
    public static let defaultMaxTurns = 10

    public static func traceIncludeSensitiveData(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let value = environment["CLINDESK_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA"] ?? "true"
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

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
    public var modelProvider: (any ModelProvider)?
    public var modelSettings: ModelSettings?
    public var handoffInputFilter: HandoffInputFilter<Context>?
    public var nestHandoffHistory: Bool
    public var handoffHistoryMapper: HandoffHistoryMapper?
    public var maxTurns: Int?
    public var workflowName: String
    public var traceID: String?
    public var groupID: String?
    public var traceMetadata: [String: JSONValue]
    public var traceIncludeSensitiveData: Bool
    public var tracingDisabled: Bool
    public var tracingProcessors: [any TracingProcessor]
    public var hooks: RunHooks<Context>
    public var session: (any Session)?
    public var sessionInputCallback: SessionInputCallback?
    public var sessionSettings: SessionSettings?
    public var reasoningItemIDPolicy: ReasoningItemIDPolicy?
    public var callModelInputFilter: CallModelInputFilter<Context>?
    public var inputGuardrails: [InputGuardrail<Context>]
    public var outputGuardrails: [OutputGuardrail<Context>]
    public var toolErrorFormatter: ToolErrorFormatter<Context>?
    public var toolNotFoundBehavior: ToolNotFoundBehavior
    public var toolExecution: ToolExecutionConfig
    public var errorHandlers: RunErrorHandlers<Context>?
    var streamEventHandler: RunnerStreamEventHandler<Context>?

    public init(
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelProvider: (any ModelProvider)? = nil,
        modelSettings: ModelSettings? = nil,
        handoffInputFilter: HandoffInputFilter<Context>? = nil,
        nestHandoffHistory: Bool = false,
        handoffHistoryMapper: HandoffHistoryMapper? = nil,
        maxTurns: Int? = RunConfigDefaults.defaultMaxTurns,
        workflowName: String = "Agent workflow",
        traceID: String? = nil,
        groupID: String? = nil,
        traceMetadata: [String: JSONValue] = [:],
        traceIncludeSensitiveData: Bool = RunConfigDefaults.traceIncludeSensitiveData(),
        tracingDisabled: Bool = false,
        tracingProcessors: [any TracingProcessor] = [],
        hooks: RunHooks<Context> = RunHooks(),
        session: (any Session)? = nil,
        sessionInputCallback: SessionInputCallback? = nil,
        sessionSettings: SessionSettings? = nil,
        reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil,
        callModelInputFilter: CallModelInputFilter<Context>? = nil,
        inputGuardrails: [InputGuardrail<Context>] = [],
        outputGuardrails: [OutputGuardrail<Context>] = [],
        toolErrorFormatter: ToolErrorFormatter<Context>? = nil,
        toolNotFoundBehavior: ToolNotFoundBehavior = .raiseError,
        toolExecution: ToolExecutionConfig = ToolExecutionConfig(),
        errorHandlers: RunErrorHandlers<Context>? = nil
    ) {
        self.model = model
        self.modelName = modelName
        self.modelProvider = modelProvider
        self.modelSettings = modelSettings
        self.handoffInputFilter = handoffInputFilter
        self.nestHandoffHistory = nestHandoffHistory
        self.handoffHistoryMapper = handoffHistoryMapper
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
        self.sessionSettings = sessionSettings
        self.reasoningItemIDPolicy = reasoningItemIDPolicy
        self.callModelInputFilter = callModelInputFilter
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.toolErrorFormatter = toolErrorFormatter
        self.toolNotFoundBehavior = toolNotFoundBehavior
        self.toolExecution = toolExecution
        self.errorHandlers = errorHandlers
        self.streamEventHandler = nil
    }
}
