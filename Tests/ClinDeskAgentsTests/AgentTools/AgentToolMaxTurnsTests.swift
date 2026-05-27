import Testing
import ClinDeskAgents

@Suite
struct AgentToolMaxTurnsTests {
    @Test
    func agentAsToolKeepsDefaultMaxTurnsWhenParentRunConfigDisablesLimit() async throws {
        let childTool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in
            .text("again")
        }
        let loopingResponses = (0..<RunConfigDefaults.defaultMaxTurns).map { index in
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_again_\(index)",
                    name: "again",
                    arguments: [:]
                ))
            ])
        } + [
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Would finish if unlimited."))
            ])
        ]
        let childModel = FakeModel(loopingResponses)
        let child = Agent<Void>(name: "Child", tools: [childTool], model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Loop."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool(failureErrorFunction: nil)],
            model: parentModel
        )

        await #expect(throws: AgentsError.maxTurnsExceeded(RunConfigDefaults.defaultMaxTurns)) {
            _ = try await Runner.run(
                agent: parent,
                input: "Run",
                runConfig: RunConfig(maxTurns: nil)
            )
        }
    }
}
