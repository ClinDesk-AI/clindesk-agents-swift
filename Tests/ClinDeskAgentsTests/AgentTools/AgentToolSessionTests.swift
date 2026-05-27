import Testing
import ClinDeskAgents

@Suite
struct AgentToolSessionTests {
    @Test
    func agentAsToolForwardsNestedSession() async throws {
        let session = MemorySession(
            sessionID: "child-thread",
            items: [
                .message(AgentMessage(role: .user, content: "remembered child context"))
            ]
        )
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "fresh child input"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool(session: session)],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        #expect(childRequests.first?.input == [
            .message(AgentMessage(role: .user, content: "remembered child context")),
            .message(AgentMessage(role: .user, content: "fresh child input"))
        ])
        let sessionItems = try await session.getItems()
        #expect(sessionItems.contains(.message(AgentMessage(role: .assistant, content: "Child answer."))))
    }
}
