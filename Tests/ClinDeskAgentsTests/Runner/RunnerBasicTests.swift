import Testing
import ClinDeskAgents

@Suite(.serialized)
struct RunnerBasicTests {
    @Test
    func returnsFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Hello from Swift."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Be concise."),
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "Hi")

        #expect(result.finalOutput == "Hello from Swift.")
        #expect(result.lastAgentName == "Assistant")
        #expect(result.lastAgent.name == "Assistant")
        #expect(result.lastAgent.handoffDescription == nil)
        #expect(result.input == [.message(AgentMessage(role: .user, content: "Hi"))])
        #expect(result.newItems == [
            .message(AgentMessage(role: .assistant, content: "Hello from Swift."))
        ])
        #expect(result.toInputList() == result.input + result.newItems)
    }

    @Test
    func typedRunDecodesStructuredOutputAndPassesSchema() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: #"{"answer":"Ready"}"#))
            ])
        ])
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"]
            ]
        ]
        let strictSchema: JSONValue = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "answer": ["type": "string"]
            ],
            "required": ["answer"]
        ]
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Return a structured answer."),
            model: model
        )

        let result = try await Runner.run(
            agent: agent,
            input: "Hi",
            outputType: StructuredAnswer.self,
            outputSchema: schema
        )

        #expect(result.finalOutput == StructuredAnswer(answer: "Ready"))
        #expect(result.rawFinalOutput == #"{"answer":"Ready"}"#)
        #expect(result.lastAgentName == "Assistant")
        #expect(result.lastAgent.name == "Assistant")
        #expect(result.input == [.message(AgentMessage(role: .user, content: "Hi"))])
        #expect(result.toInputList() == result.input + result.newItems)
        let requests = await model.requests()
        #expect(requests.first?.outputSchema?.name == "StructuredAnswer")
        #expect(requests.first?.outputSchema?.jsonSchema == strictSchema)
        #expect(requests.first?.outputSchema?.strictJSONSchema == true)
    }

    @Test
    func typedRunExposesOriginalAgentToHooks() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: #"{"answer":"Ready"}"#))
            ])
        ])
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"]
            ]
        ]
        let observations = AgentSchemaObservations()
        let hooks = RunHooks<Void>(
            onLLMStart: { _, agent, _, _ in
                await observations.record(agent.outputSchema != nil)
            },
            onLLMEnd: { _, agent, _ in
                await observations.record(agent.outputSchema != nil)
            },
            onAgentStart: { _, agent in
                await observations.record(agent.outputSchema != nil)
            },
            onAgentEnd: { _, agent, _ in
                await observations.record(agent.outputSchema != nil)
            }
        )
        let agent = Agent<Void>(
            name: "Assistant",
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hi",
            outputType: StructuredAnswer.self,
            outputSchema: schema,
            hooks: hooks
        )

        #expect(await observations.values == [false, false, false, false])
        let requests = await model.requests()
        #expect(requests.first?.outputSchema?.name == "StructuredAnswer")
    }

    @Test
    func typedRunRejectsInvalidStructuredOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "plain text"))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        do {
            _ = try await Runner.run(
                agent: agent,
                input: "Hi",
                outputType: StructuredAnswer.self
            )
            Issue.record("Expected invalid structured output")
        } catch AgentsError.invalidStructuredOutput {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func runResultDecodesFinalOutputAfterRun() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: #"{"answer":"Ready"}"#))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(agent: agent, input: "Hi")

        #expect(try result.finalOutput(as: StructuredAnswer.self) == StructuredAnswer(answer: "Ready"))
        #expect(try result.finalOutputAs(StructuredAnswer.self) == StructuredAnswer(answer: "Ready"))
    }

    @Test
    func defaultAgentRunnerCanBeOverriddenAndReset() async throws {
        let runner = RecordingAgentRunner()
        Runner.setDefaultAgentRunner(runner)
        #expect(Runner.getDefaultAgentRunner() === runner)

        Runner.setDefaultAgentRunner()
        #expect(Runner.getDefaultAgentRunner() !== runner)
    }
}

private final class RecordingAgentRunner: AgentRunner, @unchecked Sendable {
    override func run<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> RunResult {
        RunResult(
            input: input,
            finalOutput: "recorded",
            lastAgentName: agent.name,
            trace: .noOp(),
            newItems: []
        )
    }
}

private actor AgentSchemaObservations {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}
