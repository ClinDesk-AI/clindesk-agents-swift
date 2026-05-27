import Testing
import ClinDeskAgents

@Suite
struct RunStreamLifecycleTests {
    @Test
    func runStreamEmitsLifecycleEvents() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Streamed."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        var sawAgent = false
        var sawModel = false
        var sawFinal = false
        for try await event in Runner.runStream(agent: agent, input: "Hi") {
            switch event {
            case .agentUpdatedStreamEvent(let event):
                sawAgent = event.newAgent.name == "Assistant"
            case .modelResponseEvent(let event):
                if case .completed = event.data {
                    sawModel = true
                }
            case .runItemStreamEvent(let event):
                if case .messageOutputItem(let item) = event.item {
                    sawFinal = item.rawItem.content == "Streamed."
                }
            }
        }

        #expect(sawAgent)
        #expect(sawModel)
        #expect(sawFinal)
    }

    @Test
    func streamEventsExposeUpstreamTypeNames() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Streamed."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        var typeNames: [String] = []
        var runItemNames: [String] = []
        var runItemTypes: [String] = []
        for try await event in Runner.runStream(agent: agent, input: "Hi") {
            switch event {
            case .agentUpdatedStreamEvent(let event):
                typeNames.append(event.type)
            case .modelResponseEvent(let event):
                typeNames.append(event.type)
            case .runItemStreamEvent(let event):
                typeNames.append(event.type)
                runItemNames.append(event.name.rawValue)
                runItemTypes.append(event.item.type)
            }
        }

        #expect(typeNames.contains("agent_updated_stream_event"))
        #expect(typeNames.contains("model_response_event"))
        #expect(typeNames.contains("run_item_stream_event"))
        #expect(runItemNames.contains("message_output_created"))
        #expect(runItemTypes.contains("message_output_item"))
    }

    @Test
    func runStreamedTracksCompletionStateAndFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(
                output: [
                    .message(AgentMessage(role: .assistant, content: "Streamed."))
                ],
                usage: Usage(requests: 1, inputTokens: 2, outputTokens: 3, totalTokens: 5),
                responseID: "resp_123"
            )
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = Runner.runStreamed(agent: agent, input: "Hi")
        var eventCount = 0
        for try await _ in result.streamEvents() {
            eventCount += 1
        }

        #expect(eventCount > 0)
        #expect(result.isComplete)
        #expect(result.finalOutput == "Streamed.")
        #expect(result.lastAgentName == "Assistant")
        #expect(result.lastResponseID == "resp_123")
        #expect(result.modelResponses.count == 1)
        #expect(result.usage.totalTokens == 5)
        #expect(result.newItems == [
            .message(AgentMessage(role: .assistant, content: "Streamed."))
        ])
        #expect(result.runLoopException == nil)
    }

    @Test
    func runStreamedCancelStopsBackgroundRun() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Should not run."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "lookup", description: "Lookup.") { _, _ in
            .text("looked up")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = Runner.runStreamed(agent: agent, input: "Run")
        do {
            for try await event in result.streamEvents() {
                if case .runItemStreamEvent(let runItemEvent) = event,
                   runItemEvent.name == .toolOutput {
                    result.cancel()
                }
            }
            Issue.record("Expected cancellation to surface from stream events.")
        } catch {
            #expect(error as? AgentsError == .cancelled)
        }

        #expect(result.isComplete)
        #expect(result.runLoopException as? AgentsError == .cancelled)
        #expect(result.finalOutput == nil)
        #expect((await model.requests()).count == 1)
    }

    @Test
    func runStreamedExposesInterruptionsAndResumeState() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Approved."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("ran")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let streamed = Runner.runStreamed(agent: agent, input: "Run")
        for try await _ in streamed.streamEvents() {}

        #expect(streamed.isComplete)
        #expect(streamed.finalOutput == nil)
        #expect(streamed.interruptions.first?.callID == "call_sensitive")

        var state = try #require(streamed.toState(as: Void.self))
        state.approve(try #require(streamed.interruptions.first))
        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Approved.")
    }

    @Test
    func runStreamedRetainsInputGuardrailResultsWhenTripwireThrows() async throws {
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "blocked") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked input", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, inputGuardrails: [guardrail])

        let streamed = Runner.runStreamed(agent: agent, input: "Nope")

        do {
            for try await _ in streamed.streamEvents() {}
            Issue.record("Expected input guardrail tripwire.")
        } catch {
            #expect(error as? AgentsError == AgentsError.inputGuardrailTripwire(
                name: "blocked",
                reason: "blocked input"
            ))
        }

        #expect(streamed.isComplete)
        #expect(streamed.runLoopException as? AgentsError == AgentsError.inputGuardrailTripwire(
            name: "blocked",
            reason: "blocked input"
        ))
        #expect(streamed.inputGuardrailResults == [
            InputGuardrailResult(
                guardrailName: "blocked",
                output: GuardrailFunctionOutput(outputInfo: "blocked input", tripwireTriggered: true)
            )
        ])
        #expect(await model.requests().isEmpty)
    }
}
