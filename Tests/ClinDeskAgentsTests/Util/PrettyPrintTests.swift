import Testing
import ClinDeskAgents

@Suite
struct PrettyPrintTests {
    @Test
    func prettyPrintsRunResultUsingLocalModelResponseTerminology() {
        let result = RunResult(
            input: [.message(AgentMessage(role: .user, content: "Hello"))],
            finalOutput: "Hi there",
            lastAgentName: "test_agent",
            trace: .noOp(),
            newItems: [.message(AgentMessage(role: .assistant, content: "Hi there"))],
            modelResponses: [
                ModelResponse(output: [
                    .message(AgentMessage(role: .assistant, content: "Hi there"))
                ])
            ]
        )

        #expect(prettyPrintResult(result) == """
        RunResult:
        - Last agent: Agent(name="test_agent", ...)
        - Final output (String):
            Hi there
        - 1 new item(s)
        - 1 model response(s)
        - 0 input guardrail result(s)
        - 0 output guardrail result(s)
        (See `RunResult` for more details)
        """)
        #expect(result.prettyPrinted() == prettyPrintResult(result))
        #expect(String(describing: result) == prettyPrintResult(result))
    }

    @Test
    func prettyPrintsTypedRunResultAsFormattedJSONWhenEncodable() {
        let result = TypedRunResult(
            input: [.message(AgentMessage(role: .user, content: "Hello"))],
            finalOutput: PrettyAnswer(bar: "Hi there"),
            rawFinalOutput: #"{"bar":"Hi there"}"#,
            lastAgentName: "test_agent",
            trace: .noOp(),
            newItems: [.message(AgentMessage(role: .assistant, content: #"{"bar":"Hi there"}"#))],
            modelResponses: [
                ModelResponse(output: [
                    .message(AgentMessage(role: .assistant, content: #"{"bar":"Hi there"}"#))
                ])
            ]
        )

        #expect(prettyPrintResult(result) == """
        TypedRunResult:
        - Last agent: Agent(name="test_agent", ...)
        - Final output (PrettyAnswer):
            {
              "bar" : "Hi there"
            }
        - 1 new item(s)
        - 1 model response(s)
        - 0 input guardrail result(s)
        - 0 output guardrail result(s)
        (See `TypedRunResult` for more details)
        """)
        #expect(result.prettyPrinted() == prettyPrintResult(result))
    }

    @Test
    func prettyPrintsStreamingRunResultUsingUpstreamShape() async throws {
        let model = FakeModel([
            ModelResponse(
                output: [
                    .message(AgentMessage(role: .assistant, content: "Hi there"))
                ],
                responseID: "resp_123"
            )
        ])
        let agent = Agent<Void>(name: "test_agent", model: model)

        let result = Runner.runStreamed(agent: agent, input: "Hello", maxTurns: 7)
        for try await _ in result.streamEvents() {}

        #expect(prettyPrintRunResultStreaming(result) == """
        RunResultStreaming:
        - Current agent: Agent(name="test_agent", ...)
        - Current turn: 1
        - Max turns: 7
        - Is complete: true
        - Final output (String):
            Hi there
        - 1 new item(s)
        - 1 model response(s)
        - 0 input guardrail result(s)
        - 0 output guardrail result(s)
        (See `RunResultStreaming` for more details)
        """)
        #expect(result.prettyPrinted() == prettyPrintRunResultStreaming(result))
        #expect(String(describing: result) == prettyPrintRunResultStreaming(result))
    }

    @Test
    func prettyPrintsRunErrorDetailsUsingUpstreamShape() {
        let agent = Agent<Void>(name: "test_agent")
        let details = RunErrorDetails(
            input: [.message(AgentMessage(role: .user, content: "Hello"))],
            newItems: [.message(AgentMessage(role: .assistant, content: "Working"))],
            history: [
                .message(AgentMessage(role: .user, content: "Hello")),
                .message(AgentMessage(role: .assistant, content: "Working"))
            ],
            output: [.message(AgentMessage(role: .assistant, content: "Working"))],
            modelResponses: [
                ModelResponse(output: [
                    .message(AgentMessage(role: .assistant, content: "Working"))
                ])
            ],
            lastAgent: agent,
            inputGuardrailResults: [
                InputGuardrailResult(
                    guardrailName: "input",
                    output: GuardrailFunctionOutput(outputInfo: "ok", tripwireTriggered: false)
                )
            ],
            outputGuardrailResults: [
                OutputGuardrailResult(
                    guardrailName: "output",
                    agentName: "test_agent",
                    agentOutput: "Working",
                    output: GuardrailFunctionOutput(outputInfo: "ok", tripwireTriggered: false)
                )
            ]
        )

        #expect(prettyPrintRunErrorDetails(details) == """
        RunErrorDetails:
        - Last agent: Agent(name="test_agent", ...)
        - 1 new item(s)
        - 1 model response(s)
        - 1 input guardrail result(s)
        - 1 output guardrail result(s)
        (See `RunErrorDetails` for more details)
        """)
        #expect(details.prettyPrinted() == prettyPrintRunErrorDetails(details))
    }
}

private struct PrettyAnswer: Codable, Equatable, Sendable {
    var bar: String
}
