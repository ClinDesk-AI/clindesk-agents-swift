import Testing
import ClinDeskAgents

@Suite
struct TracingProcessorTests {
    @Test
    func tracingProcessorReceivesTraceStartAndEndUnlessDisabled() async throws {
        let processor = InMemoryTracingProcessor()
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Traced."))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Not traced."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Hi",
            runConfig: RunConfig(
                workflowName: "Trace test",
                tracingProcessors: [processor]
            )
        )

        let starts = await processor.startedTraces()
        let traces = await processor.allTraces()
        #expect(starts.count == 1)
        #expect(traces.count == 1)
        #expect(starts.first?.workflowName == "Trace test")
        #expect(traces.first?.workflowName == "Trace test")

        _ = try await Runner.run(
            agent: agent,
            input: "Hi again",
            runConfig: RunConfig(
                tracingDisabled: true,
                tracingProcessors: [processor]
            )
        )

        #expect(await processor.startedTraces().count == 1)
        #expect(await processor.allTraces().count == 1)
    }
}
