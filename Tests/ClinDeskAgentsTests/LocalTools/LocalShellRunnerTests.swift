import Testing
import ClinDeskAgents

actor LocalShellRecorder {
    private var calls: [LocalShellCall] = []

    func record(_ call: LocalShellCall) {
        calls.append(call)
    }

    func all() -> [LocalShellCall] {
        calls
    }
}

@Suite
struct LocalShellRunnerTests {
    @Test
    func runnerExecutesLocalShellCallsAndFeedsOutputBackToModel() async throws {
        let recorder = LocalShellRecorder()
        let shellCall = LocalShellCall(
            id: "lsh_123",
            callID: "call_shell",
            action: [
                "type": "exec",
                "command": ["bash", "-lc", "echo shell"],
                "timeout_ms": 1000,
                "working_directory": "/tmp"
            ],
            status: "completed"
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "running shell")),
                .localShellCall(shellCall)
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "shell complete"))
            ])
        ])
        let tool = LocalShellTool<Void> { request in
            await recorder.record(request.data)
            return "shell result"
        }
        let agent = Agent<Void>(
            name: "shell-agent",
            tools: [.localShell(tool)],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "please run shell")

        #expect(result.finalOutput == "shell complete")
        #expect(await recorder.all() == [shellCall])
        #expect(result.newItems.contains(ModelInputItem.localShellCall(shellCall)))
        #expect(result.newItems.contains(ModelInputItem.localShellCallOutput(LocalShellCallOutput(
            callID: "call_shell",
            output: "shell result"
        ))))

        let requests = await model.requests()
        let secondInput = try #require(requests.last?.input)
        #expect(secondInput.contains(ModelInputItem.localShellCallOutput(LocalShellCallOutput(
            callID: "call_shell",
            output: "shell result"
        ))))
    }
}
