import Foundation

extension RunnerLoop {
    func validateConfig() throws {
        if let maxTurns = config.maxTurns, maxTurns < 0 {
            throw AgentsError.invalidRunConfig("maxTurns must be non-negative.")
        }
        if let limit = config.toolExecution.maxFunctionToolConcurrency, limit < 1 {
            throw AgentsError.invalidRunConfig("toolExecution.maxFunctionToolConcurrency must be at least 1.")
        }
    }

    func filteredModelInputData(
        agent: Agent<Context>,
        context: RunContext<Context>,
        input: [ModelInputItem],
        instructions: String?
    ) async throws -> ModelInputData {
        let modelData = ModelInputData(input: input, instructions: instructions)
        guard let filter = config.callModelInputFilter else {
            return modelData
        }
        return try await filter(CallModelData(
            modelData: modelData,
            agent: agent,
            context: context.context
        ))
    }

    func resolveModel(for agent: Agent<Context>) async throws -> any Model {
        if let model = config.model {
            return model
        }
        if let model = agent.model {
            return model
        }
        if let provider = modelProvider ?? config.modelProvider {
            return try await provider.model(named: config.modelName ?? agent.modelName)
        }
        throw AgentsError.missingModel(agentName: agent.name)
    }

    func resolvedModelSettings(for agent: Agent<Context>) -> ModelSettings {
        let agentImplicitSettings = implicitModelSettings(for: agent)
        let baseSettings: ModelSettings
        if agent.modelSettings == agentImplicitSettings {
            baseSettings = modelSettingsForResolvedModelName(agent: agent)
        } else {
            baseSettings = agent.modelSettings
        }
        return baseSettings.resolve(config.modelSettings)
    }

    func implicitModelSettings(for agent: Agent<Context>) -> ModelSettings {
        if agent.model != nil {
            return ModelSettings()
        }
        if let modelName = agent.modelName {
            return DefaultModels.defaultModelSettings(model: modelName)
        }
        return DefaultModels.defaultModelSettings()
    }

    func modelSettingsForResolvedModelName(agent: Agent<Context>) -> ModelSettings {
        if config.model != nil {
            return ModelSettings()
        }
        if let modelName = config.modelName {
            return DefaultModels.defaultModelSettings(model: modelName)
        }
        return implicitModelSettings(for: agent)
    }

    func enabledTools(
        for agent: Agent<Context>,
        context: RunContext<Context>
    ) async throws -> [Tool<Context>] {
        var enabled: [Tool<Context>] = []
        for tool in agent.tools {
            switch tool {
            case .function(let functionTool):
                if await functionTool.isEnabled(context) {
                    try validateStrictFunctionToolSchema(functionTool)
                    enabled.append(tool)
                }
            case .computer,
                    .localShell,
                    .shell,
                    .applyPatch,
                    .custom:
                enabled.append(tool)
            }
        }
        return enabled
    }

    func enabledHandoffs(
        for agent: Agent<Context>,
        context: RunContext<Context>
    ) async throws -> [Handoff<Context>] {
        var enabled: [Handoff<Context>] = []
        for handoff in agent.handoffs where await handoff.isEnabled(context) {
            try validateStrictHandoffSchema(handoff)
            enabled.append(handoff)
        }
        return enabled
    }

    private func validateStrictFunctionToolSchema(_ tool: FunctionTool<Context>) throws {
        guard tool.descriptor.strict else {
            return
        }
        do {
            _ = try StrictSchema.ensureStrictJSONSchema(tool.descriptor.parameters)
        } catch {
            throw AgentsError.invalidRunConfig(
                "Invalid strict JSON schema for function tool '\(tool.descriptor.qualifiedName)': \(error.localizedDescription)"
            )
        }
    }

    private func validateStrictHandoffSchema(_ handoff: Handoff<Context>) throws {
        do {
            _ = try StrictSchema.ensureStrictJSONSchema(handoff.descriptor.inputSchema)
        } catch {
            throw AgentsError.invalidRunConfig(
                "Invalid strict JSON schema for handoff '\(handoff.descriptor.toolName)': \(error.localizedDescription)"
            )
        }
    }
}
