import Testing
import ClinDeskAgents

@Suite
struct FunctionToolTimeoutTests {
    @Test
    func functionToolTimeoutReturnsModelVisibleErrorByDefault() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_slow", name: "slow", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "slow",
            description: "Slow.",
            timeoutSeconds: 0.001
        ) { _, _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return .text("late")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Recovered.")
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_slow"
                    && output.output.stringValue == "Tool 'slow' timed out after 0.001 seconds."
            }
            return false
        } == true)
    }

    @Test
    func functionToolTimeoutCanCustomizeOrRaiseException() async throws {
        let customModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_custom_timeout", name: "slow", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let customTool = FunctionTool<Void>(
            name: "slow",
            description: "Slow.",
            timeoutSeconds: 0.001,
            timeoutErrorFunction: { _, error in
                #expect((error as? ToolTimeoutError)?.toolName == "slow")
                return "custom timeout"
            }
        ) { _, _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return .text("late")
        }
        let customAgent = Agent<Void>(name: "Assistant", tools: [customTool], model: customModel)

        _ = try await Runner.run(agent: customAgent, input: "Run")

        let customRequests = await customModel.requests()
        #expect(customRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_custom_timeout"
                    && output.output.stringValue == "custom timeout"
            }
            return false
        } == true)

        let throwingModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_throwing_timeout", name: "slow", arguments: [:]))
            ])
        ])
        let throwingTool = FunctionTool<Void>(
            name: "slow",
            description: "Slow.",
            timeoutSeconds: 0.001,
            timeoutBehavior: .raiseException
        ) { _, _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return .text("late")
        }
        let throwingAgent = Agent<Void>(name: "Assistant", tools: [throwingTool], model: throwingModel)

        await #expect(throws: ToolTimeoutError(toolName: "slow", timeoutSeconds: 0.001)) {
            _ = try await Runner.run(agent: throwingAgent, input: "Run")
        }
    }
}
