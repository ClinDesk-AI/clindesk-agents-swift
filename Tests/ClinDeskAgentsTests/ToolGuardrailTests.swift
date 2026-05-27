import Testing
import ClinDeskAgents

@Suite
struct ToolGuardrailTests {
    @Test
    func toolInputGuardrailStopsToolExecution() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ])
        ])
        let guardrail = ToolInputGuardrail<Void>(name: "tool_input") { _ in
            ToolGuardrailFunctionOutput.raiseException(outputInfo: "bad input")
        }
        let tool = FunctionTool<Void>(
            name: "guarded",
            description: "Guarded.",
            inputGuardrails: [guardrail]
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: AgentsError.toolInputRejected(toolName: "guarded", reason: "bad input")) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func toolOutputGuardrailStopsAfterToolExecution() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ])
        ])
        let guardrail = ToolOutputGuardrail<Void>(name: "tool_output") { _, _ in
            ToolGuardrailFunctionOutput.raiseException(outputInfo: "bad output")
        }
        let tool = FunctionTool<Void>(
            name: "guarded",
            description: "Guarded.",
            outputGuardrails: [guardrail]
        ) { _, _ in
            .text("bad")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: AgentsError.toolOutputRejected(toolName: "guarded", reason: "bad output")) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func toolInputGuardrailCanRejectContentAndContinue() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let guardrail = ToolInputGuardrail<Void>(name: "tool_input_reject") { _ in
            ToolGuardrailFunctionOutput.rejectContent(
                message: "Input rejected by guardrail.",
                outputInfo: "rejected input"
            )
        }
        let tool = FunctionTool<Void>(
            name: "guarded",
            description: "Guarded.",
            inputGuardrails: [guardrail]
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Recovered.")
        #expect(result.toolInputGuardrailResults == [
            ToolInputGuardrailResult(
                guardrailName: "tool_input_reject",
                toolName: "guarded",
                callID: "call_guarded",
                output: ToolGuardrailFunctionOutput.rejectContent(
                    message: "Input rejected by guardrail.",
                    outputInfo: "rejected input"
                )
            )
        ])
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_guarded"
                    && output.output.stringValue == "Input rejected by guardrail."
            }
            return false
        } == true)
    }

    @Test
    func toolOutputGuardrailCanRejectContentAndContinue() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let guardrail = ToolOutputGuardrail<Void>(name: "tool_output_reject") { _, _ in
            ToolGuardrailFunctionOutput.rejectContent(
                message: "Output rejected by guardrail.",
                outputInfo: "rejected output"
            )
        }
        let tool = FunctionTool<Void>(
            name: "guarded",
            description: "Guarded.",
            outputGuardrails: [guardrail]
        ) { _, _ in
            .text("unsafe output")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Recovered.")
        #expect(result.toolOutputGuardrailResults == [
            ToolOutputGuardrailResult(
                guardrailName: "tool_output_reject",
                toolName: "guarded",
                callID: "call_guarded",
                output: ToolGuardrailFunctionOutput.rejectContent(
                    message: "Output rejected by guardrail.",
                    outputInfo: "rejected output"
                )
            )
        ])
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_guarded"
                    && output.output.stringValue == "Output rejected by guardrail."
            }
            return false
        } == true)
    }

    @Test
    func runResultIncludesSuccessfulToolGuardrailResults() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let inputGuardrail = ToolInputGuardrail<Void>(name: "tool_input_ok") { context in
            ToolGuardrailFunctionOutput.allow(outputInfo: context.call.callID)
        }
        let outputGuardrail = ToolOutputGuardrail<Void>(name: "tool_output_ok") { _, output in
            ToolGuardrailFunctionOutput.allow(outputInfo: output.finalOutputText)
        }
        let tool = FunctionTool<Void>(
            name: "guarded",
            description: "Guarded.",
            inputGuardrails: [inputGuardrail],
            outputGuardrails: [outputGuardrail]
        ) { _, _ in
            .text("allowed")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.toolInputGuardrailResults == [
            ToolInputGuardrailResult(
                guardrailName: "tool_input_ok",
                toolName: "guarded",
                callID: "call_guarded",
                output: ToolGuardrailFunctionOutput.allow(outputInfo: "call_guarded")
            )
        ])
        #expect(result.toolOutputGuardrailResults == [
            ToolOutputGuardrailResult(
                guardrailName: "tool_output_ok",
                toolName: "guarded",
                callID: "call_guarded",
                output: ToolGuardrailFunctionOutput.allow(outputInfo: "allowed")
            )
        ])
    }
}
