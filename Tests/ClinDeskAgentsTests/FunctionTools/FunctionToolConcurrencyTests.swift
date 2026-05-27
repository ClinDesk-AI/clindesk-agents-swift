import Testing
import ClinDeskAgents

@Suite
struct FunctionToolConcurrencyTests {
    @Test
    func toolExecutionConcurrencyMatchesRunConfigLimit() async throws {
        let limitedTracker = ConcurrencyTracker()
        let limitedTool = FunctionTool<Void>(name: "work", description: "Work.") { _, _ in
            await limitedTracker.enter()
            try await Task.sleep(nanoseconds: 10_000_000)
            await limitedTracker.leave()
            return .text("done")
        }
        let limitedModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "work", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_2", name: "work", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Limited."))
            ])
        ])
        let limitedAgent = Agent<Void>(name: "Assistant", tools: [limitedTool], model: limitedModel)

        _ = try await Runner.run(
            agent: limitedAgent,
            input: "Run",
            runConfig: RunConfig(toolExecution: ToolExecutionConfig(maxFunctionToolConcurrency: 1))
        )

        #expect(await limitedTracker.maxObserved() == 1)

        let defaultTracker = ConcurrencyTracker()
        let defaultTool = FunctionTool<Void>(name: "work", description: "Work.") { _, _ in
            await defaultTracker.enter()
            try await Task.sleep(nanoseconds: 10_000_000)
            await defaultTracker.leave()
            return .text("done")
        }
        let defaultModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "work", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_2", name: "work", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Default."))
            ])
        ])
        let defaultAgent = Agent<Void>(name: "Assistant", tools: [defaultTool], model: defaultModel)

        _ = try await Runner.run(agent: defaultAgent, input: "Run")

        #expect(await defaultTracker.maxObserved() == 2)
    }
}
