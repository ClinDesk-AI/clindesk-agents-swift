import Foundation

public enum Instructions<Context: Sendable>: Sendable {
    public typealias Builder = @Sendable (RunContext<Context>, Agent<Context>) async throws -> String?

    case text(String)
    case dynamic(Builder)

    public func resolve(context: RunContext<Context>, agent: Agent<Context>) async throws -> String? {
        switch self {
        case .text(let value):
            return value
        case .dynamic(let builder):
            return try await builder(context, agent)
        }
    }
}

private func initialModelSettings(model: (any Model)?, modelName: String?) -> ModelSettings {
    if model != nil {
        return ModelSettings()
    }
    if let modelName {
        return DefaultModels.defaultModelSettings(model: modelName)
    }
    return DefaultModels.defaultModelSettings()
}

private func modelSettingsMatchImplicitDefaults(
    model: (any Model)?,
    modelName: String?,
    modelSettings: ModelSettings
) -> Bool {
    modelSettings == initialModelSettings(model: model, modelName: modelName)
}

final class PublicAgentBox<Context: Sendable>: @unchecked Sendable {
    let agent: Agent<Context>

    init(_ agent: Agent<Context>) {
        self.agent = agent
    }
}

public struct Agent<Context: Sendable>: Sendable {
    let identityKey: String
    public var name: String
    public var handoffDescription: String?
    public var instructions: Instructions<Context>?
    public var prompt: AgentPrompt<Context>?
    public var tools: [Tool<Context>]
    public var handoffs: [Handoff<Context>]
    public var model: (any Model)?
    public var modelName: String?
    public var modelSettings: ModelSettings
    public var inputGuardrails: [InputGuardrail<Context>]
    public var outputGuardrails: [OutputGuardrail<Context>]
    public var outputSchema: AgentOutputSchema?
    public var toolUseBehavior: ToolUseBehavior<Context>
    public var resetToolChoice: Bool
    public var hooks: AgentHooks<Context>?
    var publicAgentBox: PublicAgentBox<Context>?

    public init(
        name: String,
        handoffDescription: String? = nil,
        instructions: Instructions<Context>? = nil,
        prompt: AgentPrompt<Context>? = nil,
        tools: [Tool<Context>] = [],
        handoffs: [Handoff<Context>] = [],
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings = DefaultModels.defaultModelSettings(),
        inputGuardrails: [InputGuardrail<Context>] = [],
        outputGuardrails: [OutputGuardrail<Context>] = [],
        outputSchema: AgentOutputSchema? = nil,
        toolUseBehavior: ToolUseBehavior<Context> = .runModelAgain,
        resetToolChoice: Bool = true,
        hooks: AgentHooks<Context>? = nil
    ) {
        self.identityKey = UUID().uuidString
        self.name = name
        self.handoffDescription = handoffDescription
        self.instructions = instructions
        self.prompt = prompt
        self.tools = tools
        self.handoffs = handoffs
        self.model = model
        self.modelName = modelName
        if modelSettings == DefaultModels.defaultModelSettings() {
            self.modelSettings = initialModelSettings(model: model, modelName: modelName)
        } else {
            self.modelSettings = modelSettings
        }
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
        self.outputSchema = outputSchema
        self.toolUseBehavior = toolUseBehavior
        self.resetToolChoice = resetToolChoice
        self.hooks = hooks
    }

    public func clone(
        name: String? = nil,
        handoffDescription: String? = nil,
        instructions: Instructions<Context>? = nil,
        prompt: AgentPrompt<Context>? = nil,
        tools: [Tool<Context>]? = nil,
        handoffs: [Handoff<Context>]? = nil,
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings? = nil,
        inputGuardrails: [InputGuardrail<Context>]? = nil,
        outputGuardrails: [OutputGuardrail<Context>]? = nil,
        outputSchema: AgentOutputSchema? = nil,
        toolUseBehavior: ToolUseBehavior<Context>? = nil,
        resetToolChoice: Bool? = nil,
        hooks: AgentHooks<Context>? = nil
    ) -> Agent<Context> {
        let resolvedModel = model ?? self.model
        let resolvedModelName = modelName ?? self.modelName
        let resolvedModelSettings: ModelSettings
        if let modelSettings {
            resolvedModelSettings = modelSettings
        } else if (model != nil || modelName != nil) && modelSettingsMatchImplicitDefaults(
            model: self.model,
            modelName: self.modelName,
            modelSettings: self.modelSettings
        ) {
            resolvedModelSettings = initialModelSettings(model: resolvedModel, modelName: resolvedModelName)
        } else {
            resolvedModelSettings = self.modelSettings
        }

        var cloned = Agent(
            name: name ?? self.name,
            handoffDescription: handoffDescription ?? self.handoffDescription,
            instructions: instructions ?? self.instructions,
            prompt: prompt ?? self.prompt,
            tools: tools ?? self.tools,
            handoffs: handoffs ?? self.handoffs,
            model: resolvedModel,
            modelName: resolvedModelName,
            modelSettings: resolvedModelSettings,
            inputGuardrails: inputGuardrails ?? self.inputGuardrails,
            outputGuardrails: outputGuardrails ?? self.outputGuardrails,
            outputSchema: outputSchema ?? self.outputSchema,
            toolUseBehavior: toolUseBehavior ?? self.toolUseBehavior,
            resetToolChoice: resetToolChoice ?? self.resetToolChoice,
            hooks: hooks ?? self.hooks
        )
        cloned.publicAgentBox = publicAgentBox
        return cloned
    }

    var publicAgent: Agent<Context> {
        publicAgentBox?.agent ?? self
    }

    func withPublicAgent(_ publicAgent: Agent<Context>) -> Agent<Context> {
        var agent = self
        agent.publicAgentBox = PublicAgentBox(publicAgent.publicAgent)
        return agent
    }

    public func getSystemPrompt(runContext: RunContext<Context>) async throws -> String? {
        try await instructions?.resolve(context: runContext, agent: self)
    }

    public func getPrompt(runContext: RunContext<Context>) async throws -> Prompt? {
        try await prompt?.resolve(context: runContext, agent: publicAgent)
    }

    public init(
        name: String,
        handoffDescription: String? = nil,
        instructions: Instructions<Context>? = nil,
        prompt: AgentPrompt<Context>? = nil,
        tools: [FunctionTool<Context>],
        handoffs: [Handoff<Context>] = [],
        model: (any Model)? = nil,
        modelName: String? = nil,
        modelSettings: ModelSettings = DefaultModels.defaultModelSettings(),
        inputGuardrails: [InputGuardrail<Context>] = [],
        outputGuardrails: [OutputGuardrail<Context>] = [],
        outputSchema: AgentOutputSchema? = nil,
        toolUseBehavior: ToolUseBehavior<Context> = .runModelAgain,
        resetToolChoice: Bool = true,
        hooks: AgentHooks<Context>? = nil
    ) {
        self.init(
            name: name,
            handoffDescription: handoffDescription,
            instructions: instructions,
            prompt: prompt,
            tools: tools.map(Tool.function),
            handoffs: handoffs,
            model: model,
            modelName: modelName,
            modelSettings: modelSettings,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails,
            outputSchema: outputSchema,
            toolUseBehavior: toolUseBehavior,
            resetToolChoice: resetToolChoice,
            hooks: hooks
        )
    }
}
