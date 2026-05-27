import Testing
import ClinDeskAgents

private struct PromptCacheFakeModel: Model {
    let store: FakeModelStore
    let supportsDefaultPromptCacheKey = true

    init(_ responses: [ModelResponse]) {
        self.store = FakeModelStore(responses)
    }

    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        try await store.next(for: request)
    }

    func requests() async -> [CapturedModelRequest] {
        await store.requests()
    }
}

@Suite
struct PromptCacheKeyTests {
    @Test
    func defaultPromptCacheKeyIsStableAcrossSessionGroupedTurns() async throws {
        let model = PromptCacheFakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_again", name: "again", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in
            .text("again")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [.function(tool)], model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(session: MemorySession(sessionID: "session_prompt_cache"))
        )

        let requests = await model.requests()
        #expect(requests.count == 2)
        let firstKey = try #require(requests.first?.settings.extraArgs?[promptCacheKeyField]?.stringValue)
        let secondKey = try #require(requests.last?.settings.extraArgs?[promptCacheKeyField]?.stringValue)
        #expect(firstKey == secondKey)
        #expect(firstKey.hasPrefix("agents-sdk:session:"))
        #expect(firstKey.count == "agents-sdk:session:".count + 32)
    }

    @Test
    func explicitPromptCacheKeyIsNotOverwritten() async throws {
        let model = PromptCacheFakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            modelSettings: ModelSettings(extraArgs: [promptCacheKeyField: .string("manual")])
        )

        _ = try await Runner.run(agent: agent, input: "Run")

        let requests = await model.requests()
        #expect(requests.first?.settings.extraArgs?[promptCacheKeyField] == .string("manual"))
    }

    @Test
    func generatedPromptCacheKeySurvivesApprovalResume() async throws {
        let model = PromptCacheFakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let sensitive = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("sensitive")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [.function(sensitive)], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        var state = try #require(interrupted.state(as: Void.self))
        let generatedKey = try #require(state.generatedPromptCacheKey)
        #expect(generatedKey.hasPrefix("agents-sdk:run:"))

        state.approve(try #require(interrupted.interruptions.first))
        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Done.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.first?.settings.extraArgs?[promptCacheKeyField] == .string(generatedKey))
        #expect(requests.last?.settings.extraArgs?[promptCacheKeyField] == .string(generatedKey))
    }
}
