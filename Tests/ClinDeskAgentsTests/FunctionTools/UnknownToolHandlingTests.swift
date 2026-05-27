import Testing
import ClinDeskAgents

@Suite
struct UnknownToolHandlingTests {
    @Test
    func unknownToolThrowsByDefault() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_missing", name: "missing", arguments: [:]))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.toolNotFound("missing")) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func unknownToolCanReturnErrorToModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_missing", name: "missing", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(toolNotFoundBehavior: .returnErrorToModel)
        )

        #expect(result.finalOutput == "Recovered.")
        let requests = await model.requests()
        let secondRequest = requests.dropFirst().first
        #expect(secondRequest?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_missing"
            }
            return false
        } == true)
    }

    @Test
    func toolErrorFormatterCustomizesUnknownToolOutputReturnedToModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_missing", name: "missing", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                toolErrorFormatter: { args in
                    #expect(args.kind == .toolNotFound)
                    #expect(args.toolType == .function)
                    #expect(args.toolName == "missing")
                    #expect(args.callID == "call_missing")
                    #expect(args.defaultMessage == "Tool 'missing' not found.")
                    return "Custom missing tool message."
                },
                toolNotFoundBehavior: .returnErrorToModel
            )
        )

        let requests = await model.requests()
        let secondRequest = requests.dropFirst().first
        #expect(secondRequest?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_missing"
                    && output.output.stringValue == "Custom missing tool message."
            }
            return false
        } == true)
    }

    @Test
    func toolErrorFormatterFallsBackToDefaultMessageWhenNilOrThrowing() async throws {
        let nilFormatterModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_nil", name: "missing", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered nil."))
            ])
        ])
        let throwingFormatterModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_throw", name: "missing", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered throwing."))
            ])
        ])
        let nilFormatterAgent = Agent<Void>(name: "Assistant", model: nilFormatterModel)
        let throwingFormatterAgent = Agent<Void>(name: "Assistant", model: throwingFormatterModel)

        _ = try await Runner.run(
            agent: nilFormatterAgent,
            input: "Run",
            runConfig: RunConfig(
                toolErrorFormatter: { _ in nil },
                toolNotFoundBehavior: .returnErrorToModel
            )
        )
        _ = try await Runner.run(
            agent: throwingFormatterAgent,
            input: "Run",
            runConfig: RunConfig(
                toolErrorFormatter: { _ in throw AgentsError.provider("formatter failed") },
                toolNotFoundBehavior: .returnErrorToModel
            )
        )

        let nilRequests = await nilFormatterModel.requests()
        let throwingRequests = await throwingFormatterModel.requests()

        #expect(nilRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_nil"
                    && output.output.stringValue == "Tool 'missing' not found."
            }
            return false
        } == true)
        #expect(throwingRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_throw"
                    && output.output.stringValue == "Tool 'missing' not found."
            }
            return false
        } == true)
    }
}
