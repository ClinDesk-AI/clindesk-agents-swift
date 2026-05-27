import Testing
import ClinDeskAgents

@Suite
struct AgentToolNestedRunTests {
    @Test
    func agentAsToolRunsNestedAgentAndFeedsOutputBackToParent() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child Agent", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child_agent",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool()],
            model: parentModel
        )

        let result = try await Runner.run(agent: parent, input: "Run")

        #expect(result.finalOutput == "Parent done.")
        let childRequests = await childModel.requests()
        #expect(childRequests.first?.input == [
            .message(AgentMessage(role: .user, content: "Need a child answer."))
        ])
        let parentRequests = await parentModel.requests()
        #expect(parentRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_child"
                    && output.output.stringValue == "Child answer."
            }
            return false
        } == true)
    }
}
