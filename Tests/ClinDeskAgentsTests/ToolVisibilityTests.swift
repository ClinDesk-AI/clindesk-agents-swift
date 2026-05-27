import Testing
import ClinDeskAgents

@Suite
struct ToolVisibilityTests {
    @Test
    func disabledToolsAreHiddenFromModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "No tools."))
            ])
        ])
        let hiddenTool = FunctionTool<Void>(
            name: "hidden",
            description: "Hidden tool.",
            isEnabled: { _ in false }
        ) { _, _ in
            .text("hidden")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [hiddenTool], model: model)

        _ = try await Runner.run(agent: agent, input: "Hi")

        let requests = await model.requests()
        #expect(requests.first?.tools == [])
    }
}
