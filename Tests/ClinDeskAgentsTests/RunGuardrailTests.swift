import Testing
import ClinDeskAgents

@Suite
struct RunGuardrailTests {
    @Test
    func inputGuardrailStopsRun() async throws {
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "blocked") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked input", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, inputGuardrails: [guardrail])

        await #expect(throws: AgentsError.inputGuardrailTripwire(name: "blocked", reason: "blocked input")) {
            _ = try await Runner.run(agent: agent, input: "Nope")
        }
    }

    @Test
    func runConfigInputGuardrailRunsWithAgentGuardrails() async throws {
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "run_config_input") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked by run config", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.inputGuardrailTripwire(
            name: "run_config_input",
            reason: "blocked by run config"
        )) {
            _ = try await Runner.run(
                agent: agent,
                input: "Nope",
                runConfig: RunConfig(inputGuardrails: [guardrail])
            )
        }
    }

    @Test
    func inputGuardrailUsesOriginalTurnInputWithoutSessionHistory() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [.message(AgentMessage(role: .user, content: "old history"))]
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed final."))
            ])
        ])
        let guardrail = InputGuardrail<Void>(name: "original_input") { _, _, input in
            let content = input.compactMap { item -> String? in
                if case .message(let message) = item {
                    return message.content
                }
                return nil
            }.joined(separator: "|")
            return GuardrailFunctionOutput(outputInfo: content, tripwireTriggered: false)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, inputGuardrails: [guardrail])

        let result = try await Runner.run(agent: agent, input: "new input", session: session)

        #expect(result.inputGuardrailResults == [
            InputGuardrailResult(
                guardrailName: "original_input",
                output: GuardrailFunctionOutput(outputInfo: "new input", tripwireTriggered: false)
            )
        ])
    }

    @Test
    func inputGuardrailTripPersistsSessionCallbackNewTurnItems() async throws {
        let session = MemorySession(
            sessionID: "thread-1",
            items: [.message(AgentMessage(role: .user, content: "old history"))]
        )
        let rewrittenInput = ModelInputItem.message(AgentMessage(role: .user, content: "rewritten input"))
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "blocked") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked input", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, inputGuardrails: [guardrail])

        await #expect(throws: AgentsError.inputGuardrailTripwire(name: "blocked", reason: "blocked input")) {
            _ = try await Runner.run(
                agent: agent,
                input: "raw input",
                runConfig: RunConfig(
                    session: session,
                    sessionInputCallback: { _, _ in
                        [rewrittenInput]
                    }
                )
            )
        }

        #expect(try await session.getItems() == [
            .message(AgentMessage(role: .user, content: "old history")),
            rewrittenInput
        ])
        #expect(await model.requests().isEmpty)
    }

    @Test
    func outputGuardrailStopsFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "bad final"))
            ])
        ])
        let guardrail = OutputGuardrail<Void>(name: "output") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "bad final", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model, outputGuardrails: [guardrail])

        await #expect(throws: AgentsError.outputGuardrailTripwire(name: "output", reason: "bad final")) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func runConfigOutputGuardrailRunsWithAgentGuardrails() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "bad final"))
            ])
        ])
        let guardrail = OutputGuardrail<Void>(name: "run_config_output") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked by run config", tripwireTriggered: true)
        }
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.outputGuardrailTripwire(
            name: "run_config_output",
            reason: "blocked by run config"
        )) {
            _ = try await Runner.run(
                agent: agent,
                input: "Run",
                runConfig: RunConfig(outputGuardrails: [guardrail])
            )
        }
    }

    @Test
    func runResultIncludesSuccessfulGuardrailResults() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed final."))
            ])
        ])
        let inputGuardrail = InputGuardrail<Void>(name: "input_ok") { _, _, input in
            GuardrailFunctionOutput(
                outputInfo: "checked:\(input.count)",
                tripwireTriggered: false
            )
        }
        let outputGuardrail = OutputGuardrail<Void>(name: "output_ok") { _, agent, output in
            GuardrailFunctionOutput(
                outputInfo: "\(agent.name):\(output)",
                tripwireTriggered: false
            )
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            inputGuardrails: [inputGuardrail],
            outputGuardrails: [outputGuardrail]
        )

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.inputGuardrailResults == [
            InputGuardrailResult(
                guardrailName: "input_ok",
                output: GuardrailFunctionOutput(outputInfo: "checked:1", tripwireTriggered: false)
            )
        ])
        #expect(result.outputGuardrailResults == [
            OutputGuardrailResult(
                guardrailName: "output_ok",
                agentName: "Assistant",
                agentOutput: "Allowed final.",
                output: GuardrailFunctionOutput(
                    outputInfo: "Assistant:Allowed final.",
                    tripwireTriggered: false
                )
            )
        ])
    }

    @Test
    func inputGuardrailsMarkedParallelRunConcurrently() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed final."))
            ])
        ])
        let meter = GuardrailConcurrencyMeter()
        let first = InputGuardrail<Void>(name: "first") { _, _, _ in
            await meter.enter()
            try await Task.sleep(for: .milliseconds(50))
            await meter.leave()
            return GuardrailFunctionOutput(outputInfo: "first", tripwireTriggered: false)
        }
        let second = InputGuardrail<Void>(name: "second") { _, _, _ in
            await meter.enter()
            try await Task.sleep(for: .milliseconds(50))
            await meter.leave()
            return GuardrailFunctionOutput(outputInfo: "second", tripwireTriggered: false)
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            inputGuardrails: [first, second]
        )

        _ = try await Runner.run(agent: agent, input: "Run")

        #expect(await meter.maxActive == 2)
    }

    @Test
    func inputGuardrailsMarkedSequentialRunBeforeParallelGuardrails() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed final."))
            ])
        ])
        let events = GuardrailEvents()
        let sequential = InputGuardrail<Void>(name: "sequential", runInParallel: false) { _, _, _ in
            await events.append("sequential")
            return GuardrailFunctionOutput(outputInfo: "sequential", tripwireTriggered: false)
        }
        let parallel = InputGuardrail<Void>(name: "parallel") { _, _, _ in
            await events.append("parallel")
            return GuardrailFunctionOutput(outputInfo: "parallel", tripwireTriggered: false)
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            inputGuardrails: [parallel, sequential]
        )

        _ = try await Runner.run(agent: agent, input: "Run")

        #expect(await events.values.first == "sequential")
    }

    @Test
    func outputGuardrailsRunConcurrently() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed final."))
            ])
        ])
        let meter = GuardrailConcurrencyMeter()
        let first = OutputGuardrail<Void>(name: "first") { _, _, _ in
            await meter.enter()
            try await Task.sleep(for: .milliseconds(50))
            await meter.leave()
            return GuardrailFunctionOutput(outputInfo: "first", tripwireTriggered: false)
        }
        let second = OutputGuardrail<Void>(name: "second") { _, _, _ in
            await meter.enter()
            try await Task.sleep(for: .milliseconds(50))
            await meter.leave()
            return GuardrailFunctionOutput(outputInfo: "second", tripwireTriggered: false)
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            outputGuardrails: [first, second]
        )

        _ = try await Runner.run(agent: agent, input: "Run")

        #expect(await meter.maxActive == 2)
    }
}

private actor GuardrailConcurrencyMeter {
    private(set) var active = 0
    private(set) var maxActive = 0

    func enter() {
        active += 1
        maxActive = max(maxActive, active)
    }

    func leave() {
        active -= 1
    }
}

private actor GuardrailEvents {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}
