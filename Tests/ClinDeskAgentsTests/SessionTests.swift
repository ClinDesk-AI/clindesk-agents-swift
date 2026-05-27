import Testing
import ClinDeskAgents

@Suite
struct SessionTests {
    @Test
    func memorySessionStoresTurnItems() async throws {
        let session = MemorySession(sessionID: "thread-1")
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Stored."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(agent: agent, input: "Remember this", session: session)

        let items = try await session.getItems()
        #expect(items.count == 2)
    }

    @Test
    func memorySessionPopsAndClearsItems() async throws {
        let latest = ModelInputItem.message(AgentMessage(role: .assistant, content: "latest"))
        let session = MemorySession(
            sessionID: "thread-1",
            items: [
                .message(AgentMessage(role: .user, content: "old")),
                latest
            ]
        )

        #expect(session.sessionID == "thread-1")
        let popped = try await session.popItem()
        #expect(popped == latest)

        try await session.clearSession()
        #expect(try await session.getItems() == [])
    }

    @Test
    func sessionInputCallbackCanRewriteSessionHistoryForModelInput() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [.message(AgentMessage(role: .user, content: "old history"))]
        )
        let callback: SessionInputCallback = { _, newInput in
            newInput
        }
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Using callback."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "new input",
            runConfig: RunConfig(
                session: session,
                sessionInputCallback: callback
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "new input"))])
    }

    @Test
    func sessionPreparationNormalizesDeduplicatesAndPrunesHistoryOrphans() async throws {
        let orphanReasoning: JSONValue = [
            "type": "reasoning",
            "id": "rs_orphan",
            "summary": [["type": "summary_text", "text": "drop"]]
        ]
        let matchedCall = FunctionCall(
            id: "fc_matched",
            callID: "call_matched",
            name: "lookup",
            arguments: [:]
        )
        let matchedOutput = FunctionCallOutput(callID: "call_matched", output: .string("ok"))
        let oldRaw: ModelInputItem = .raw([
            "type": "reasoning",
            "id": "rs_duplicate",
            "_agents_tool_title": "internal",
            "summary": [["type": "summary_text", "text": "old"]]
        ])
        let newRaw: ModelInputItem = .raw([
            "type": "reasoning",
            "id": "rs_duplicate",
            "summary": [["type": "summary_text", "text": "new"]]
        ])
        let session = MemorySession(
            sessionID: "thread-1",
            items: [
                oldRaw,
                .reasoning(orphanReasoning),
                .functionCall(FunctionCall(
                    id: "fc_orphan",
                    callID: "call_orphan",
                    name: "lookup",
                    arguments: [:]
                )),
                .functionCall(matchedCall),
                .functionCallOutput(matchedOutput)
            ]
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Prepared."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(agent: agent, input: [newRaw], session: session)

        let requests = await model.requests()
        #expect(requests.first?.input == [
            .functionCall(matchedCall),
            .functionCallOutput(matchedOutput),
            newRaw
        ])
    }

    @Test
    func sessionInputCallbackPreservesNewTurnToolCallsThatLookOrphaned() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [
                .functionCall(FunctionCall(
                    id: "fc_old",
                    callID: "call_old",
                    name: "lookup",
                    arguments: [:]
                ))
            ]
        )
        let newCall = FunctionCall(
            id: "fc_new",
            callID: "call_new",
            name: "lookup",
            arguments: [:]
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Prepared."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: [.functionCall(newCall)],
            runConfig: RunConfig(
                session: session,
                sessionInputCallback: { _, newInput in
                    newInput
                }
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [.functionCall(newCall)])
    }

    @Test
    func sessionInputCallbackPersistsRewrittenNewTurnItemsOnly() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [.message(AgentMessage(role: .user, content: "old history"))]
        )
        let rewrittenInput = ModelInputItem.message(AgentMessage(role: .user, content: "rewritten input"))
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Stored rewrite."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "raw input",
            runConfig: RunConfig(
                session: session,
                sessionInputCallback: { _, _ in
                    [rewrittenInput]
                }
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [rewrittenInput])
        #expect(try await session.getItems() == [
            .message(AgentMessage(role: .user, content: "old history")),
            rewrittenInput,
            .message(AgentMessage(role: .assistant, content: "Stored rewrite."))
        ])
    }

    @Test
    func sessionSettingsLimitControlsMemorySessionHistory() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [
                .message(AgentMessage(role: .user, content: "old user")),
                .message(AgentMessage(role: .assistant, content: "old assistant")),
                .message(AgentMessage(role: .user, content: "latest user"))
            ],
            sessionSettings: SessionSettings(limit: 1)
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Limited history."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(agent: agent, input: "new input", session: session)

        let requests = await model.requests()
        #expect(requests.first?.input == [
            .message(AgentMessage(role: .user, content: "latest user")),
            .message(AgentMessage(role: .user, content: "new input"))
        ])
    }

    @Test
    func runConfigSessionSettingsOverrideSessionDefaults() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [
                .message(AgentMessage(role: .user, content: "old user")),
                .message(AgentMessage(role: .assistant, content: "old assistant")),
                .message(AgentMessage(role: .user, content: "latest user"))
            ],
            sessionSettings: SessionSettings(limit: 1)
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Override history."))
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
    func sessionSettingsResolveAndDictionaryMirrorUpstream() {
        #expect(SessionSettings(limit: 1).resolve(nil) == SessionSettings(limit: 1))
        #expect(SessionSettings(limit: 1).resolve(SessionSettings(limit: nil)) == SessionSettings(limit: 1))
        #expect(SessionSettings(limit: 1).resolve(SessionSettings(limit: 3)) == SessionSettings(limit: 3))
        #expect(SessionSettings.resolveLimit(explicitLimit: 2, settings: SessionSettings(limit: 1)) == 2)
        #expect(SessionSettings.resolveLimit(explicitLimit: nil, settings: SessionSettings(limit: 1)) == 1)
        #expect(SessionSettings.resolveLimit(explicitLimit: nil, settings: nil) == nil)
        #expect(SessionSettings(limit: 4).toDictionary() == ["limit": .number(4)])
        #expect(SessionSettings(limit: nil).toDictionary() == ["limit": .null])
    }
}
