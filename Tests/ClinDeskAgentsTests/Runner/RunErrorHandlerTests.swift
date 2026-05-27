import Testing
import ClinDeskAgents

@Suite
struct RunErrorHandlerTests {
    @Test
    func maxTurnsHandlerCanReturnFinalOutput() async throws {
        let model = FakeModel([])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                maxTurns: 0,
                errorHandlers: RunErrorHandlers(maxTurns: { input in
                    #expect(input.error == .maxTurnsExceeded(0))
                    #expect(input.runData.input == [
                        .message(AgentMessage(role: .user, content: "Run"))
                    ])
                    #expect(input.runData.history == input.runData.input)
                    #expect(input.runData.output == [])
                    #expect(input.runData.modelResponses == [])
                    #expect(input.runData.lastAgent.name == "Assistant")
                    return RunErrorHandlerResult(finalOutput: "summary:\(input.runData.history.count)")
                })
            )
        )

        #expect(result.finalOutput == "summary:1")
        #expect(result.newItems.contains(.message(AgentMessage(
            role: .assistant,
            content: "summary:1"
        ))))
    }

    @Test
    func runErrorDetailsIncludeCompletedInputGuardrails() async throws {
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "input_ok") { _, _, input in
            GuardrailFunctionOutput(outputInfo: "checked:\(input.count)", tripwireTriggered: false)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, inputGuardrails: [guardrail])

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                maxTurns: 0,
                errorHandlers: RunErrorHandlers(maxTurns: { input in
                    #expect(input.runData.inputGuardrailResults == [
                        InputGuardrailResult(
                            guardrailName: "input_ok",
                            output: GuardrailFunctionOutput(outputInfo: "checked:1", tripwireTriggered: false)
                        )
                    ])
                    #expect(input.runData.outputGuardrailResults == [])
                    return RunErrorHandlerResult(finalOutput: input.runData.prettyPrinted())
                })
            )
        )

        #expect(result.finalOutput.contains("- 1 input guardrail result(s)"))
        #expect(result.finalOutput.contains("- 0 output guardrail result(s)"))
    }

    @Test
    func maxTurnsHandlerCanSkipHistory() async throws {
        let model = FakeModel([])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                maxTurns: 0,
                errorHandlers: RunErrorHandlers(maxTurns: { _ in
                    RunErrorHandlerResult(finalOutput: "summary", includeInHistory: false)
                })
            )
        )

        #expect(result.finalOutput == "summary")
        #expect(!result.newItems.contains(.message(AgentMessage(
            role: .assistant,
            content: "summary"
        ))))
    }

    @Test
    func typedRunCanDecodeMaxTurnsHandlerOutput() async throws {
        let model = FakeModel([])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            outputType: StructuredAnswer.self,
            runConfig: RunConfig(
                maxTurns: 0,
                errorHandlers: RunErrorHandlers(maxTurns: { _ in
                    RunErrorHandlerResult(finalOutput: #"{"answer":"handled"}"#)
                })
            )
        )

        #expect(result.finalOutput == StructuredAnswer(answer: "handled"))
        #expect(result.rawFinalOutput == #"{"answer":"handled"}"#)
    }

    @Test
    func modelRefusalThrowsWithoutHandler() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .refusal("I cannot help with that request.")
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.modelRefusal("I cannot help with that request.")) {
            _ = try await Runner.run(
                agent: agent,
                input: "Run",
                outputType: StructuredAnswer.self
            )
        }

        let requests = await model.requests()
        #expect(requests.count == 1)
    }

    @Test
    func modelRefusalHandlerCanReturnFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .refusal("I cannot help with that request.")
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                errorHandlers: RunErrorHandlers(modelRefusal: { input in
                    #expect(input.error == .modelRefusal("I cannot help with that request."))
                    #expect(input.runData.input == [
                        .message(AgentMessage(role: .user, content: "Run"))
                    ])
                    #expect(input.runData.output == [
                        .refusal("I cannot help with that request.")
                    ])
                    #expect(input.runData.modelResponses.count == 1)
                    #expect(input.runData.lastAgent.name == "Assistant")
                    return RunErrorHandlerResult(finalOutput: "safe fallback")
                })
            )
        )

        #expect(result.finalOutput == "safe fallback")
        #expect(result.newItems.contains(.refusal("I cannot help with that request.")))
        #expect(result.newItems.contains(.message(AgentMessage(
            role: .assistant,
            content: "safe fallback"
        ))))
    }

    @Test
    func modelRefusalHandlerCanSkipHistory() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .refusal("I cannot help with that request.")
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                errorHandlers: RunErrorHandlers(modelRefusal: { _ in
                    RunErrorHandlerResult(finalOutput: "safe fallback", includeInHistory: false)
                })
            )
        )

        #expect(result.finalOutput == "safe fallback")
        #expect(result.newItems.contains(.refusal("I cannot help with that request.")))
        #expect(!result.newItems.contains(.message(AgentMessage(
            role: .assistant,
            content: "safe fallback"
        ))))
    }

    @Test
    func typedRunCanDecodeModelRefusalHandlerOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .refusal("I cannot help with that request.")
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            outputType: StructuredAnswer.self,
            runConfig: RunConfig(
                errorHandlers: RunErrorHandlers(modelRefusal: { _ in
                    RunErrorHandlerResult(finalOutput: #"{"answer":"safe fallback"}"#)
                })
            )
        )

        #expect(result.finalOutput == StructuredAnswer(answer: "safe fallback"))
        #expect(result.rawFinalOutput == #"{"answer":"safe fallback"}"#)
    }
}
