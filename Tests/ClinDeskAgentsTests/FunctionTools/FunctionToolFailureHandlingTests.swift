import Testing
import ClinDeskAgents

@Suite
struct FunctionToolFailureHandlingTests {
    @Test
    func functionToolFailuresReturnModelVisibleErrorByDefault() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_fail", name: "fail", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "fail", description: "Fail.") { _, _ in
            throw AgentsError.provider("boom")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Recovered.")
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_fail"
                    && output.output.stringValue == "An error occurred while running the tool. Please try again. Error: boom"
            }
            return false
        } == true)
    }

    @Test
    func functionToolFailureErrorFunctionCanCustomizeOrDisableHandling() async throws {
        let customModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_custom_fail", name: "fail", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let customTool = FunctionTool<Void>(
            name: "fail",
            description: "Fail.",
            failureErrorFunction: { _, error in
                #expect(error.localizedDescription == "boom")
                return "custom failure"
            }
        ) { _, _ in
            throw AgentsError.provider("boom")
        }
        let customAgent = Agent<Void>(name: "Assistant", tools: [customTool], model: customModel)

        _ = try await Runner.run(agent: customAgent, input: "Run")

        let customRequests = await customModel.requests()
        #expect(customRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_custom_fail"
                    && output.output.stringValue == "custom failure"
            }
            return false
        } == true)

        let disabledModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_disabled_fail", name: "fail", arguments: [:]))
            ])
        ])
        let disabledTool = FunctionTool<Void>(
            name: "fail",
            description: "Fail.",
            failureErrorFunction: nil
        ) { _, _ in
            throw AgentsError.provider("boom")
        }
        let disabledAgent = Agent<Void>(name: "Assistant", tools: [disabledTool], model: disabledModel)

        await #expect(throws: AgentsError.provider("boom")) {
            _ = try await Runner.run(agent: disabledAgent, input: "Run")
        }
    }
}
