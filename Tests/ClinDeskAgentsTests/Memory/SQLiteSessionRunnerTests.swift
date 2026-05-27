import Testing
import ClinDeskAgents

@Suite
struct SQLiteSessionRunnerTests {
    @Test
    func runnerUsesSQLiteSessionHistoryAcrossTurns() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("runner.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "runner", dbPath: temp.path)
        defer { session.close() }
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "San Francisco"))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "California"))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(agent: agent, input: "What city is the Golden Gate Bridge in?", session: session)
        _ = try await Runner.run(agent: agent, input: "What state is it in?", session: session)

        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests[1].input == [
            .message(AgentMessage(role: .user, content: "What city is the Golden Gate Bridge in?")),
            .message(AgentMessage(role: .assistant, content: "San Francisco")),
            .message(AgentMessage(role: .user, content: "What state is it in?"))
        ])
        #expect(try await session.getItems() == [
            .message(AgentMessage(role: .user, content: "What city is the Golden Gate Bridge in?")),
            .message(AgentMessage(role: .assistant, content: "San Francisco")),
            .message(AgentMessage(role: .user, content: "What state is it in?")),
            .message(AgentMessage(role: .assistant, content: "California"))
        ])
    }

    @Test
    func runConfigSessionSettingsLimitSQLiteHistoryForRunner() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("runner-limit.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "runner_limit", dbPath: temp.path)
        defer { session.close() }
        try await session.addItems([
            .message(AgentMessage(role: .user, content: "old user")),
            .message(AgentMessage(role: .assistant, content: "old assistant")),
            .message(AgentMessage(role: .user, content: "latest user"))
        ])
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Limited history."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "new input",
            runConfig: RunConfig(
                session: session,
                sessionSettings: SessionSettings(limit: 2)
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [
            .message(AgentMessage(role: .assistant, content: "old assistant")),
            .message(AgentMessage(role: .user, content: "latest user")),
            .message(AgentMessage(role: .user, content: "new input"))
        ])
    }

    @Test
    func sessionInputCallbackCanRewriteSQLiteHistoryForRunner() async throws {
        let temp = try SQLiteSessionTestSupport.temporaryDatabasePath("runner-callback.db")
        defer { temp.cleanup() }
        let session = try SQLiteSession(sessionID: "runner_callback", dbPath: temp.path)
        defer { session.close() }
        try await session.addItems([
            .message(AgentMessage(role: .user, content: "keep me")),
            .message(AgentMessage(role: .assistant, content: "drop me"))
        ])
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "new input",
            runConfig: RunConfig(
                session: session,
                sessionInputCallback: { history, newInput in
                    history.filter { $0.testMessageContent == "keep me" } + newInput
                }
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [
            .message(AgentMessage(role: .user, content: "keep me")),
            .message(AgentMessage(role: .user, content: "new input"))
        ])
    }
}
