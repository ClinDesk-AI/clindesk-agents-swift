import Testing
import ClinDeskAgents

@Suite
struct AgentToolApprovalResumeTests {
    @Test
    func agentAsToolSurfacesNestedApprovalInterruptionAndResumesChildRun() async throws {
        let sensitive = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("approved child tool")
        }
        let childModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child approved."))
            ])
        ])
        let child = Agent<Void>(name: "Child", tools: [sensitive], model: childModel)
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

        let interrupted = try await Runner.run(agent: parent, input: "Run")

        #expect(interrupted.isInterrupted)
        #expect(interrupted.interruptions.first?.toolName == "sensitive")
        #expect(interrupted.interruptions.first?.callID == "call_sensitive")
        #expect(await parentModel.requests().count == 1)

        var state = try #require(interrupted.state(as: Void.self))
        state.approve(try #require(interrupted.interruptions.first))

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Parent done.")
        let childRequests = await childModel.requests()
        #expect(childRequests.count == 2)
        #expect(childRequests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_sensitive"
                    && output.output.stringValue == "approved child tool"
            }
            return false
        } == true)
        let parentRequests = await parentModel.requests()
        #expect(parentRequests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_child"
                    && output.output.stringValue == "Child approved."
            }
            return false
        } == true)
    }
}
