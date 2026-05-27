import Testing
import ClinDeskAgents

@Suite
struct ComputerToolSafetyTests {
    @Test
    func pendingSafetyChecksAreAcknowledgedBeforeComputerActionRuns() async throws {
        let computer = RecordingComputer()
        let recorder = ComputerSafetyRecorder()
        let safetyCheck = PendingComputerSafetyCheck(
            id: "cu_sc_123",
            code: "malicious_instructions",
            message: "The page contains prompt injection text."
        )
        let computerCall = ComputerCall(
            callID: "call_safe",
            action: ComputerAction(type: "move", x: 1, y: 2),
            pendingSafetyChecks: [safetyCheck]
        )
        let model = FakeModel([
            ModelResponse(output: [.computerCall(computerCall)]),
            ModelResponse(output: [.message(AgentMessage(role: .assistant, content: "safe done"))])
        ])
        let tool = ComputerTool<Void>(computer: computer) { data in
            await recorder.record(data.safetyCheck)
            return data.toolCall.callID == "call_safe"
        }
        let agent = Agent<Void>(
            name: "computer-agent",
            tools: [.computer(tool)],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "move")

        #expect(result.finalOutput == "safe done")
        #expect(await recorder.checks() == [safetyCheck])
        #expect(computer.events == [
            .move(x: 1, y: 2, keys: nil),
            .screenshot
        ])
        #expect(result.newItems.contains(ModelInputItem.computerCallOutput(ComputerCallOutput(
            callID: "call_safe",
            output: [
                "type": "computer_screenshot",
                "image_url": "data:image/png;base64,image-data"
            ],
            acknowledgedSafetyChecks: [safetyCheck]
        ))))
    }
}
