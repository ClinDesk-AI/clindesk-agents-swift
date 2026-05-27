import Testing
import ClinDeskAgents

private actor RecordingShellExecutor {
    private var storedCalls: [ShellCall] = []

    var calls: [ShellCall] {
        storedCalls
    }

    func execute(_ request: ShellCommandRequest<Void>) async throws -> ShellToolOutput {
        storedCalls.append(request.data)
        return .text("shell ok")
    }
}

@Suite
struct ShellToolApprovalTests {
    @Test
    func shellApprovalCanInterruptAndResumeAfterApproval() async throws {
        let recorder = RecordingShellExecutor()
        let shellCall = ShellCall(
            callID: "call_shell",
            action: ShellActionRequest(commands: ["echo hi"])
        )
        let model = FakeModel([
            ModelResponse(output: [.shellCall(shellCall)]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Shell approved."))
            ])
        ])
        let tool = try ShellTool<Void>(
            executor: recorder.execute,
            needsApproval: .always
        )
        let agent = Agent<Void>(name: "sheller", tools: [.shell(tool)], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "run shell")

        #expect(interrupted.isInterrupted)
        let interruption = try #require(interrupted.interruptions.first)
        #expect(interruption.toolName == "shell")
        #expect(interruption.callID == "call_shell")
        #expect(interruption.arguments == ((try? JSONValue.encoded(shellCall.action)) ?? .emptyObject))
        #expect(interruption.tool == .shell(ShellToolDescriptor()))
        #expect(await recorder.calls.isEmpty)

        var state = try #require(interrupted.state(as: Void.self))
        state.approve(interruption)

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Shell approved.")
        #expect(await recorder.calls == [shellCall])
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .shellCallOutput(let output) = $0 {
                return output.callID == "call_shell"
                    && output.status == "completed"
                    && output.output == .string("shell ok")
            }
            return false
        } == true)
    }
}
