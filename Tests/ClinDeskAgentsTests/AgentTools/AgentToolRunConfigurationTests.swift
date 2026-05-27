import Testing
import ClinDeskAgents

@Suite
struct AgentToolRunConfigurationTests {
    @Test
    func agentAsToolInheritsParentRunConfigWhenNoRunConfigProvided() async throws {
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

        _ = try await Runner.run(
            agent: parent,
            input: "Run",
            runConfig: RunConfig(modelSettings: ModelSettings(maxOutputTokens: 123))
        )

        let childRequests = await childModel.requests()
        #expect(childRequests.first?.settings.maxOutputTokens == 123)
    }

    @Test
    func agentAsToolExplicitRunConfigOverridesInheritedParentRunConfig() async throws {
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
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(runConfig: RunConfig(modelSettings: ModelSettings(maxOutputTokens: 7)))
            ],
            model: parentModel
        )

        _ = try await Runner.run(
            agent: parent,
            input: "Run",
            runConfig: RunConfig(modelSettings: ModelSettings(maxOutputTokens: 123))
        )

        let childRequests = await childModel.requests()
        #expect(childRequests.first?.settings.maxOutputTokens == 7)
    }

    @Test
    func agentAsToolForwardsNestedRunOptions() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let hookEvents = StringRecorder()
        let hooks = RunHooks<Void>(
            onAgentStart: { _, agent in
                await hookEvents.append("start:\(agent.name)")
            }
        )
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(
                    hooks: hooks
                )
            ],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        #expect(childRequests.count == 1)
        #expect(await hookEvents.all() == ["start:Child"])
    }
}
