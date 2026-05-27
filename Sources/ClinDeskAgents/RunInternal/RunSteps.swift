struct FunctionToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: FunctionTool<Context>
    var call: FunctionCall
}

struct CustomToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: CustomTool<Context>
    var call: CustomToolCall
}

struct ComputerToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: ComputerTool<Context>
    var call: ComputerCall
}

struct LocalShellToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: LocalShellTool<Context>
    var call: LocalShellCall
}

struct ShellToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: ShellTool<Context>
    var call: ShellCall
}

struct ApplyPatchToolRun<Context: Sendable>: Sendable {
    var offset: Int
    var tool: ApplyPatchTool<Context>
    var call: ApplyPatchCall
}

struct FunctionToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [FunctionToolRun<Context>] = []
    var immediateResults: [Int: ToolRunResult] = [:]
    var interruptions: [ToolApprovalItem] = []

    var hasInterruptions: Bool {
        !interruptions.isEmpty
    }

    func orderedResults(callCount: Int) -> [ToolRunResult] {
        (0..<callCount).compactMap { immediateResults[$0] }
    }
}

struct CustomToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [CustomToolRun<Context>] = []
    var immediateResults: [Int: CustomToolRunResult] = [:]
    var interruptions: [ToolApprovalItem] = []

    var hasInterruptions: Bool {
        !interruptions.isEmpty
    }
}

struct ComputerToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [ComputerToolRun<Context>] = []
}

struct LocalShellToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [LocalShellToolRun<Context>] = []
}

struct ShellToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [ShellToolRun<Context>] = []
    var immediateResults: [Int: ShellRunResult] = [:]
    var interruptions: [ToolApprovalItem] = []

    var hasInterruptions: Bool {
        !interruptions.isEmpty
    }
}

struct ApplyPatchToolExecutionPlan<Context: Sendable>: Sendable {
    var scheduled: [ApplyPatchToolRun<Context>] = []
    var immediateResults: [Int: ApplyPatchRunResult] = [:]
    var interruptions: [ToolApprovalItem] = []

    var hasInterruptions: Bool {
        !interruptions.isEmpty
    }
}

enum ToolCallOutcome: Sendable {
    case completed([ToolRunResult])
    case interrupted([ToolApprovalItem])
}

enum CustomToolCallOutcome: Sendable {
    case completed([CustomToolRunResult])
    case interrupted([ToolApprovalItem])
}

enum ComputerToolCallOutcome: Sendable {
    case completed([ComputerRunResult])
}

enum LocalShellToolCallOutcome: Sendable {
    case completed([LocalShellRunResult])
}

enum ShellToolCallOutcome: Sendable {
    case completed([ShellRunResult])
    case interrupted([ToolApprovalItem])
}

enum ApplyPatchToolCallOutcome: Sendable {
    case completed([ApplyPatchRunResult])
    case interrupted([ToolApprovalItem])
}

struct HandoffTurnResolution<Context: Sendable>: Sendable {
    var agent: Agent<Context>
    var resultInput: [ModelInputItem]
    var modelInput: [ModelInputItem]
    var newItems: [ModelInputItem]
    var shouldRunAgentStartHooks: Bool
}

struct ProcessedModelResponse: Sendable {
    var preHandoffItems: [ModelInputItem]
    var inputHistory: [ModelInputItem]
    var outputInputItems: [ModelInputItem]
    var modelInput: [ModelInputItem]
    var newItems: [ModelInputItem]
    var handoffCalls: [FunctionCall]
    var toolCalls: [FunctionCall]
    var unknownFunctionCalls: [FunctionCall]
    var customToolCalls: [CustomToolCall]
    var unknownCustomToolCalls: [CustomToolCall]
    var computerCalls: [ComputerCall]
    var unknownComputerCalls: [ComputerCall]
    var localShellCalls: [LocalShellCall]
    var unknownLocalShellCalls: [LocalShellCall]
    var shellCalls: [ShellCall]
    var unknownShellCalls: [ShellCall]
    var applyPatchCalls: [ApplyPatchCall]
    var unknownApplyPatchCalls: [ApplyPatchCall]
}

struct ToolSideEffectState<Context: Sendable>: Sendable {
    var runContext: RunContext<Context>
    var modelInput: [ModelInputItem]
    var newItems: [ModelInputItem]
    var toolUseTracker: AgentToolUseTracker<Context>
    var toolInputGuardrailResults: [ToolInputGuardrailResult]
    var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
}

struct ToolUseResolution: Sendable {
    var isFinalOutput: Bool
    var finalOutput: String

    static let notFinal = ToolUseResolution(isFinalOutput: false, finalOutput: "")
}

enum ToolSideEffectOutcome<Context: Sendable>: Sendable {
    case runAgain(ToolSideEffectState<Context>)
    case completed(RunResult)
}

struct RunLoopState<Context: Sendable>: Sendable {
    var runContext: RunContext<Context>
    var trace: Trace
    var currentAgent: Agent<Context>
    var resultInput: [ModelInputItem]
    var sessionInputItems: [ModelInputItem]
    var modelInput: [ModelInputItem]
    var newItems: [ModelInputItem]
    var modelResponses: [ModelResponse]
    var lastResponseID: String?
    var toolUseTracker: AgentToolUseTracker<Context>
    var shouldRunAgentStartHooks: Bool
    var inputGuardrailResults: [InputGuardrailResult]
    var toolInputGuardrailResults: [ToolInputGuardrailResult]
    var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    var promptCacheKeyResolver: PromptCacheKeyResolver<Context>
    var turn: Int
}

struct RunLoopStartResult<Context: Sendable>: Sendable {
    var state: RunLoopState<Context>
    var completedResult: RunResult?
}
