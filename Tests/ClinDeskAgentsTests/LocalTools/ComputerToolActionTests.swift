import Testing
import ClinDeskAgents

@Suite
struct ComputerToolActionTests {
    @Test
    func runnerExecutesComputerActionsAndFeedsScreenshotBackToModel() async throws {
        let computer = RecordingComputer()
        let computerCall = ComputerCall(
            id: "cu_123",
            callID: "call_computer",
            actions: [
                ComputerAction(type: "click", x: 10, y: 20, button: .left, keys: ["CMD"]),
                ComputerAction(type: "type", text: "hello")
            ],
            status: "completed"
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "using computer")),
                .computerCall(computerCall)
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "computer complete"))
            ])
        ])
        let agent = Agent<Void>(
            name: "computer-agent",
            tools: [.computer(ComputerTool(computer: computer))],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "click and type")

        #expect(result.finalOutput == "computer complete")
        #expect(computer.events == [
            .click(x: 10, y: 20, button: .left, keys: ["CMD"]),
            .type("hello"),
            .screenshot
        ])
        #expect(result.newItems.contains(ModelInputItem.computerCall(computerCall)))

        let output = ComputerCallOutput(
            callID: "call_computer",
            output: [
                "type": "computer_screenshot",
                "image_url": "data:image/png;base64,image-data"
            ]
        )
        #expect(result.newItems.contains(ModelInputItem.computerCallOutput(output)))

        let secondInput = try #require(await model.requests().last?.input)
        #expect(secondInput.contains(ModelInputItem.computerCallOutput(output)))
    }

    @Test
    func screenshotActionIsNotCapturedTwice() async throws {
        let computer = RecordingComputer()
        computer.screenshotImage = "already-captured"
        let computerCall = ComputerCall(
            callID: "call_screenshot",
            action: ComputerAction(type: "screenshot")
        )
        let model = FakeModel([
            ModelResponse(output: [.computerCall(computerCall)]),
            ModelResponse(output: [.message(AgentMessage(role: .assistant, content: "done"))])
        ])
        let agent = Agent<Void>(
            name: "computer-agent",
            tools: [.computer(ComputerTool(computer: computer))],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "capture")

        #expect(result.finalOutput == "done")
        #expect(computer.events == [.screenshot])
        #expect(result.newItems.contains(ModelInputItem.computerCallOutput(ComputerCallOutput(
            callID: "call_screenshot",
            output: [
                "type": "computer_screenshot",
                "image_url": "data:image/png;base64,already-captured"
            ]
        ))))
    }
}
