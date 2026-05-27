import Testing
import ClinDeskAgents

@Suite
struct MaxTurnsTests {
    @Test
    func maxTurnsExceededAndNilDisablesLimit() async throws {
        let limitedModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "again", arguments: [:]))
            ], responseID: "resp_1"),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Too late."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in .text("again") }
        let limitedAgent = Agent<Void>(name: "Assistant", tools: [tool], model: limitedModel)

        await #expect(throws: AgentsError.maxTurnsExceeded(1)) {
            _ = try await Runner.run(agent: limitedAgent, input: "Run", maxTurns: 1)
        }

        let unlimitedModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "again", arguments: [:]))
            ], responseID: "resp_1"),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let unlimitedAgent = Agent<Void>(name: "Assistant", tools: [tool], model: unlimitedModel)

        let result = try await Runner.run(
            agent: unlimitedAgent,
            input: "Run",
            runConfig: RunConfig(maxTurns: nil)
        )

        #expect(result.finalOutput == "Done.")
    }

    @Test
    func maxTurnsExceededPersistsSessionInputWithoutHandler() async throws {
        let session = MemorySession(sessionID: "max_turns_zero")
        let model = FakeModel([])
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.maxTurnsExceeded(0)) {
            _ = try await Runner.run(
                agent: agent,
                input: "Run",
                runConfig: RunConfig(maxTurns: 0, session: session)
            )
        }

        #expect(try await session.getItems() == [
            .message(AgentMessage(role: .user, content: "Run"))
        ])
    }

    @Test
    func maxTurnsExceededPersistsCompletedTurnItemsWithoutHandler() async throws {
        let session = MemorySession(sessionID: "max_turns_after_tool")
        let call = FunctionCall(id: "fc_1", callID: "call_1", name: "again", arguments: [:])
        let model = FakeModel([
            ModelResponse(output: [.functionCall(call)], responseID: "resp_1")
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in
            .text("again")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: AgentsError.maxTurnsExceeded(1)) {
            _ = try await Runner.run(
                agent: agent,
                input: "Run",
                runConfig: RunConfig(maxTurns: 1, session: session)
            )
        }

        #expect(try await session.getItems() == [
            .message(AgentMessage(role: .user, content: "Run")),
            .functionCall(call),
            .functionCallOutput(FunctionCallOutput(callID: "call_1", output: .string("again")))
        ])
    }
}
