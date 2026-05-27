import Testing
import ClinDeskAgents

@Suite
struct DefaultModelsTests {
    @Test
    func defaultModelSettingsUseLocalDefaults() {
        #expect(DefaultModels.defaultModel(environment: [
            "CLINDESK_AGENTS_DEFAULT_MODEL": "LOCAL-CLINIC"
        ]) == "local-clinic")
        #expect(DefaultModels.defaultModel(environment: [:]) == "local")
        #expect(DefaultModels.defaultModelSettings(model: "local-clinic") == ModelSettings())
    }

    @Test
    func runnerUsesRunConfigModelProvider() async throws {
        let namedModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Named response."))
            ])
        ])
        let provider = StaticModelProvider(
            defaultModel: namedModel,
            namedModels: ["local-clinic": namedModel]
        )
        let agent = Agent<Void>(name: "Assistant", modelName: "local-clinic")

        let result = try await Runner.run(
            agent: agent,
            input: "Hi",
            runConfig: RunConfig(modelProvider: provider)
        )

        #expect(result.finalOutput == "Named response.")
    }

    @Test
    func runnerAppliesImplicitSettingsForNamedModels() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let provider = StaticModelProvider(
            defaultModel: model,
            namedModels: ["local-clinic": model]
        )
        let agent = Agent<Void>(name: "Assistant", modelName: "local-clinic")

        _ = try await Runner.run(agent: agent, input: "Hi", modelProvider: provider)

        let requests = await model.requests()
        #expect(requests.first?.settings == DefaultModels.defaultModelSettings(model: "local-clinic"))
    }

    @Test
    func multiProviderRoutesPrefixedModelNamesToMappedLocalProvider() async throws {
        let clinicModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Clinic response."))
            ])
        ])
        let clinicProvider = StaticModelProvider(
            defaultModel: clinicModel,
            namedModels: ["triage": clinicModel]
        )
        let providerMap = MultiProviderMap(["clinic": clinicProvider])
        let provider = MultiProvider(providerMap: providerMap)
        let agent = Agent<Void>(name: "Assistant", modelName: "clinic/triage")

        let result = try await Runner.run(agent: agent, input: "Hi", modelProvider: provider)

        #expect(result.finalOutput == "Clinic response.")
        #expect((await clinicModel.requests()).count == 1)
    }

    @Test
    func multiProviderCanPassUnknownPrefixesToDefaultProviderAsModelIDs() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Namespaced response."))
            ])
        ])
        let defaultProvider = StaticModelProvider(
            defaultModel: model,
            namedModels: ["local/triage": model]
        )
        let provider = MultiProvider(
            defaultProvider: defaultProvider,
            unknownPrefixMode: .modelID
        )
        let agent = Agent<Void>(name: "Assistant", modelName: "local/triage")

        let result = try await Runner.run(agent: agent, input: "Hi", modelProvider: provider)

        #expect(result.finalOutput == "Namespaced response.")
    }

    @Test
    func multiProviderFailsUnknownPrefixesByDefault() async throws {
        let provider = MultiProvider()
        await #expect(throws: AgentsError.modelNotFound("missing/model")) {
            _ = try await provider.model(named: "missing/model")
        }
    }
}
