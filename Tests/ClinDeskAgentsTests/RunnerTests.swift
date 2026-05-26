#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import Testing
import ClinDeskAgents
import ClinDeskAgentsOpenAI

@Suite
struct RunnerTests {
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
        let requests = await model.requests()
        #expect(requests.first?.outputSchema == schema)
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
    func resolvesDynamicInstructionsWithContext() async throws {
        struct ClinicContext: Sendable {
            let clinicName: String
        }

        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Ready."))
            ])
        ])
        let agent = Agent<ClinicContext>(
            name: "Assistant",
            instructions: .dynamic { context, _ in
                "You are helping \(context.context?.clinicName ?? "the clinic")."
            },
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hola",
            context: ClinicContext(clinicName: "ClinDesk Clinic")
        )

        let requests = await model.requests()
        #expect(requests.first?.instructions == "You are helping ClinDesk Clinic.")
    }

    @Test
    func modelProviderResolvesNamedModel() async throws {
        let namedModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Named model response."))
            ])
        ])
        let fallbackModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Fallback."))
            ])
        ])
        let provider = StaticModelProvider(
            defaultModel: fallbackModel,
            namedModels: ["gpt-test": namedModel]
        )
        let agent = Agent<Void>(name: "Assistant", modelName: "gpt-test")

        let result = try await Runner.run(agent: agent, input: "Hi", modelProvider: provider)

        #expect(result.finalOutput == "Named model response.")
    }

    @Test
    func runConfigCallModelInputFilterCanRewriteModelData() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Original instructions."),
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Original input",
            runConfig: RunConfig(callModelInputFilter: { data in
                ModelInputData(
                    input: [.message(AgentMessage(role: .user, content: "Filtered input"))],
                    instructions: "\(data.agent.name): filtered instructions"
                )
            })
        )

        let requests = await model.requests()
        #expect(requests.first?.instructions == "Assistant: filtered instructions")
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "Filtered input"))])
    }

    @Test
    func runsFunctionToolAndFeedsResultBackToModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_weather", name: "weather", arguments: ["city": "Cancun"]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "It is sunny in Cancun."))
            ])
        ])

        struct WeatherInput: Decodable, Sendable {
            let city: String
        }

        let weather = FunctionTool<Void>(
            name: "weather",
            description: "Get the weather.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string"]
                ],
                "required": ["city"],
                "additionalProperties": false
            ]
        ) { (_: ToolContext<Void>, input: WeatherInput) in
            .json(["forecast": .string("sunny"), "city": .string(input.city)])
        }

        let agent = Agent<Void>(name: "Weather", tools: [weather], model: model)
        let result = try await Runner.run(agent: agent, input: "Weather?")

        #expect(result.finalOutput == "It is sunny in Cancun.")
        #expect(result.newItems.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_weather"
            }
            return false
        })
    }

    @Test
    func disabledToolsAreHiddenFromModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "No tools."))
            ])
        ])
        let hiddenTool = FunctionTool<Void>(
            name: "hidden",
            description: "Hidden tool.",
            isEnabled: { _ in false }
        ) { _, _ in
            .text("hidden")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [hiddenTool], model: model)

        _ = try await Runner.run(agent: agent, input: "Hi")

        let requests = await model.requests()
        #expect(requests.first?.tools == [])
    }

    @Test
    func typedToolRejectsNonObjectArguments() async throws {
        struct Input: Decodable, Sendable {
            let value: String
        }

        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_bad", name: "typed", arguments: ["not", "object"]))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "typed",
            description: "Typed tool.",
            parameters: ["type": "object"]
        ) { (_: ToolContext<Void>, _: Input) in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: AgentsError.invalidToolArguments(
            toolName: "typed",
            reason: "Function tool input must be a JSON object."
        )) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func stopOnFirstToolReturnsTextOutputWithoutJSONQuoting() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_quote", name: "quote", arguments: [:]))
            ])
        ])
        let quote = FunctionTool<Void>(name: "quote", description: "Return a quote.") { _, _ in
            .text("1200 MXN")
        }
        let agent = Agent<Void>(
            name: "Quoter",
            tools: [quote],
            model: model,
            toolUseBehavior: .stopOnFirstTool
        )

        let result = try await Runner.run(agent: agent, input: "Quote?")

        #expect(result.finalOutput == "1200 MXN")
    }

    @Test
    func stopAtToolsStopsOnlyForConfiguredToolNames() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_a", name: "first", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_b", name: "second", arguments: [:]))
            ])
        ])
        let first = FunctionTool<Void>(name: "first", description: "First.") { _, _ in .text("first") }
        let second = FunctionTool<Void>(name: "second", description: "Second.") { _, _ in .text("second") }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [first, second],
            model: model,
            toolUseBehavior: .stopAtTools(["second"])
        )

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "second")
    }

    @Test
    func customToolUseBehaviorCanReturnFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_done", name: "done", arguments: [:]))
            ])
        ])
        let done = FunctionTool<Void>(name: "done", description: "Done.") { _, _ in .text("tool output") }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [done],
            model: model,
            toolUseBehavior: .custom { _, results in
                ToolsToFinalOutputResult(
                    isFinalOutput: true,
                    finalOutput: "custom: \(results.first?.output.finalOutputText ?? "")"
                )
            }
        )

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "custom: tool output")
    }

    @Test
    func toolExecutionConcurrencyMatchesRunConfigLimit() async throws {
        let limitedTracker = ConcurrencyTracker()
        let limitedTool = FunctionTool<Void>(name: "work", description: "Work.") { _, _ in
            await limitedTracker.enter()
            try await Task.sleep(nanoseconds: 10_000_000)
            await limitedTracker.leave()
            return .text("done")
        }
        let limitedModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "work", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_2", name: "work", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Limited."))
            ])
        ])
        let limitedAgent = Agent<Void>(name: "Assistant", tools: [limitedTool], model: limitedModel)

        _ = try await Runner.run(
            agent: limitedAgent,
            input: "Run",
            runConfig: RunConfig(toolExecution: ToolExecutionConfig(maxFunctionToolConcurrency: 1))
        )

        #expect(await limitedTracker.maxObserved() == 1)

        let defaultTracker = ConcurrencyTracker()
        let defaultTool = FunctionTool<Void>(name: "work", description: "Work.") { _, _ in
            await defaultTracker.enter()
            try await Task.sleep(nanoseconds: 10_000_000)
            await defaultTracker.leave()
            return .text("done")
        }
        let defaultModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_1", name: "work", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_2", name: "work", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Default."))
            ])
        ])
        let defaultAgent = Agent<Void>(name: "Assistant", tools: [defaultTool], model: defaultModel)

        _ = try await Runner.run(agent: defaultAgent, input: "Run")

        #expect(await defaultTracker.maxObserved() == 2)
    }

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
    func approvalRejectionStopsToolExecution() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in false }
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: AgentsError.approvalRejected(toolName: "sensitive")) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func toolInputGuardrailStopsToolExecution() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_guarded", name: "guarded", arguments: [:]))
            ])
        ])
        let guardrail = ToolInputGuardrail<Void>(name: "tool_input") { _ in
            GuardrailFunctionOutput(outputInfo: "bad input", tripwireTriggered: true)
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
            GuardrailFunctionOutput(outputInfo: "bad output", tripwireTriggered: true)
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
    func handoffSwitchesAgents() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "I can help book that appointment."))
            ])
        ])
        let booking = Agent<Void>(
            name: "Booking",
            handoffDescription: "Books appointments.",
            model: bookingModel
        )
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        let result = try await Runner.run(agent: triage, input: "Need an appointment")

        #expect(result.finalOutput == "I can help book that appointment.")
        #expect(result.lastAgentName == "Booking")
    }

    @Test
    func handoffInputFilterCanRewriteModelInput() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(
                    to: booking,
                    toolName: "transfer_to_booking",
                    isEnabled: { _ in true },
                    inputFilter: { _ in
                        [.message(AgentMessage(role: .user, content: "filtered input"))]
                    }
                )
            ],
            model: triageModel
        )

        _ = try await Runner.run(agent: triage, input: "original")

        let requests = await bookingModel.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "filtered input"))])
    }

    @Test
    func runConfigHandoffInputFilterAppliesWhenHandoffDoesNotOverride() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered by run config."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        _ = try await Runner.run(
            agent: triage,
            input: "original",
            runConfig: RunConfig(handoffInputFilter: { _ in
                [.message(AgentMessage(role: .user, content: "run config filtered input"))]
            })
        )

        let requests = await bookingModel.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "run config filtered input"))])
    }

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
    func memorySessionStoresTurnItems() async throws {
        let session = MemorySession(id: "thread-1")
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Stored."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(agent: agent, input: "Remember this", session: session)

        let items = try await session.getItems()
        #expect(items.count == 2)
    }

    @Test
    func sessionInputCallbackCanRewriteSessionHistoryForModelInput() async throws {
        let session = MemorySession(
            id: "thread-1",
            items: [.message(AgentMessage(role: .user, content: "old history"))]
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Using callback."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "new input",
            runConfig: RunConfig(
                session: session,
                sessionInputCallback: { _, newInput in
                    newInput
                }
            )
        )

        let requests = await model.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "new input"))])
    }

    @Test
    func sessionCannotBeCombinedWithServerManagedConversation() async throws {
        let session = MemorySession(id: "thread-1")
        let model = FakeModel([])
        let agent = Agent<Void>(name: "Assistant", model: model)

        await #expect(throws: AgentsError.invalidRunConfig(
            "Session memory cannot be combined with previousResponseID, autoPreviousResponseID, or conversationID."
        )) {
            _ = try await Runner.run(
                agent: agent,
                input: "Hi",
                previousResponseID: "resp_old",
                session: session
            )
        }
    }

    @Test
    func tracingProcessorReceivesCompletedTraceUnlessDisabled() async throws {
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

        let traces = await processor.allTraces()
        #expect(traces.count == 1)
        #expect(traces.first?.workflowName == "Trace test")

        _ = try await Runner.run(
            agent: agent,
            input: "Hi again",
            runConfig: RunConfig(
                tracingDisabled: true,
                tracingProcessors: [processor]
            )
        )

        #expect(await processor.allTraces().count == 1)
    }

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
            case .agentStarted:
                sawAgent = true
            case .modelCompleted:
                sawModel = true
            case .finalOutput(let output):
                sawFinal = output == "Streamed."
            default:
                break
            }
        }

        #expect(sawAgent)
        #expect(sawModel)
        #expect(sawFinal)
    }

    @Test
    func maxTurnsExceededAndNilDisablesLimit() async throws {
        let limitedModel = FakeModel([
            ModelResponse(id: "resp_1", output: [
                .functionCall(FunctionCall(callID: "call_1", name: "again", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Too late."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in .text("again") }
        let limitedAgent = Agent<Void>(name: "Assistant", tools: [tool], model: limitedModel)

        await #expect(throws: AgentsError.maxTurnsExceeded(1)) {
            _ = try await Runner.run(agent: limitedAgent, input: "Run", maxTurns: 1)
        }

        let unlimitedModel = FakeModel([
            ModelResponse(id: "resp_1", output: [
                .functionCall(FunctionCall(callID: "call_1", name: "again", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let unlimitedAgent = Agent<Void>(name: "Assistant", tools: [tool], model: unlimitedModel)

        let result = try await Runner.run(
            agent: unlimitedAgent,
            input: "Run",
            runConfig: RunConfig(maxTurns: nil)
        )

        #expect(result.finalOutput == "Done.")
    }

    @Test
    func previousResponseIDIsAppliedOnceAndAutoPreviousChainsLaterTurns() async throws {
        let model = FakeModel([
            ModelResponse(id: "resp_1", output: [
                .functionCall(FunctionCall(callID: "call_1", name: "again", arguments: [:]))
            ]),
            ModelResponse(id: "resp_2", output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in .text("again") }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Run",
            previousResponseID: "resp_old",
            autoPreviousResponseID: true
        )

        let requests = await model.requests()
        #expect(requests.first?.previousResponseID == "resp_old")
        #expect(requests.dropFirst().first?.previousResponseID == "resp_1")
    }

    @Test
    func openAIProviderEncodesToolsAndDecodesFunctionCalls() async throws {
        let capture = RequestCapture()
        let response = """
        {
          "id": "resp_123",
          "output": [
            {
              "type": "function_call",
              "id": "fc_123",
              "call_id": "call_123",
              "name": "lookup",
              "arguments": "{\\"query\\":\\"clinic hours\\"}"
            }
          ],
          "usage": {
            "input_tokens": 10,
            "output_tokens": 5,
            "total_tokens": 15
          }
        }
        """.data(using: .utf8)!

        let model = OpenAIResponsesModel(
            apiKey: "test",
            organization: "org_123",
            project: "proj_123"
        ) { request in
            await capture.set(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, http)
        }

        let tool = ToolDescriptor(
            name: "lookup",
            description: "Look up clinic facts.",
            parameters: ["type": "object"]
        )
        let result = try await model.getResponse(ModelRequest<Void>(
            instructions: "Use tools.",
            input: [
                .message(AgentMessage(role: .user, content: "hours?")),
                .functionCallOutput(FunctionCallOutput(callID: "call_prior", output: .string("plain text")))
            ],
            context: RunContext(),
            settings: ModelSettings(maxOutputTokens: 200),
            tools: [tool],
            handoffs: []
        ))

        #expect(result.id == "resp_123")
        #expect(result.functionCalls.first?.name == "lookup")
        #expect(result.usage?.totalTokens == 15)

        let request = await capture.get()
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test")
        #expect(request?.value(forHTTPHeaderField: "OpenAI-Organization") == "org_123")
        #expect(request?.value(forHTTPHeaderField: "OpenAI-Project") == "proj_123")
        guard let body = request?.httpBody else {
            Issue.record("Expected OpenAI request body")
            return
        }
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json["tools"] != nil)
        #expect(json["max_output_tokens"] != nil)
        #expect(json["input"]?.arrayValue?.last?["output"]?.stringValue == "plain text")
    }

    @Test
    func openAIProviderDecodesOutputTextFallback() async throws {
        let response = """
        {
          "id": "resp_text",
          "output_text": "Fallback text"
        }
        """.data(using: .utf8)!
        let model = OpenAIResponsesModel(apiKey: "test") { request in
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, http)
        }

        let result = try await model.getResponse(ModelRequest<Void>(
            instructions: nil,
            input: [.message(AgentMessage(role: .user, content: "Hi"))],
            context: RunContext(),
            settings: ModelSettings(),
            tools: [],
            handoffs: []
        ))

        #expect(result.finalText == "Fallback text")
    }

    @Test
    func openAIProviderReportsMissingAPIKeyAndHTTPFailures() async throws {
        let missingKeyModel = OpenAIResponsesModel(apiKey: "")
        await #expect(throws: AgentsError.provider("OPENAI_API_KEY is required to use OpenAIResponsesModel.")) {
            _ = try await missingKeyModel.getResponse(ModelRequest<Void>(
                instructions: nil,
                input: [.message(AgentMessage(role: .user, content: "Hi"))],
                context: RunContext(),
                settings: ModelSettings(),
                tools: [],
                handoffs: []
            ))
        }

        let failingModel = OpenAIResponsesModel(apiKey: "test") { request in
            let http = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"error":{"message":"rate limited"}}"#.utf8), http)
        }

        await #expect(throws: (any Error).self) {
            _ = try await failingModel.getResponse(ModelRequest<Void>(
                instructions: nil,
                input: [.message(AgentMessage(role: .user, content: "Hi"))],
                context: RunContext(),
                settings: ModelSettings(),
                tools: [],
                handoffs: []
            ))
        }
    }
}

private struct CapturedModelRequest: Equatable, Sendable {
    var instructions: String?
    var input: [ModelInputItem]
    var tools: [ToolDescriptor]
    var handoffs: [HandoffDescriptor]
    var outputSchema: JSONValue?
    var previousResponseID: String?
    var conversationID: String?
    var tracing: ModelTracing
    var maxOutputTokens: Int?

    init<Context: Sendable>(_ request: ModelRequest<Context>) {
        self.instructions = request.instructions
        self.input = request.input
        self.tools = request.tools
        self.handoffs = request.handoffs
        self.outputSchema = request.outputSchema
        self.previousResponseID = request.previousResponseID
        self.conversationID = request.conversationID
        self.tracing = request.tracing
        self.maxOutputTokens = request.settings.maxOutputTokens
    }
}

private struct StructuredAnswer: Decodable, Equatable, Sendable {
    let answer: String
}

private actor FakeModelStore {
    var responses: [ModelResponse]
    var capturedRequests: [CapturedModelRequest] = []

    init(_ responses: [ModelResponse]) {
        self.responses = responses
    }

    func next<Context: Sendable>(for request: ModelRequest<Context>) throws -> ModelResponse {
        capturedRequests.append(CapturedModelRequest(request))
        guard !responses.isEmpty else {
            throw AgentsError.invalidModelResponse("No fake response queued.")
        }
        return responses.removeFirst()
    }

    func requests() -> [CapturedModelRequest] {
        capturedRequests
    }
}

private actor ConcurrencyTracker {
    private var active = 0
    private var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }

    func maxObserved() -> Int {
        maximum
    }
}

private struct FakeModel: Model {
    let store: FakeModelStore

    init(_ responses: [ModelResponse]) {
        self.store = FakeModelStore(responses)
    }

    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        try await store.next(for: request)
    }

    func requests() async -> [CapturedModelRequest] {
        await store.requests()
    }
}

private actor RequestCapture {
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        self.request = request
    }

    func get() -> URLRequest? {
        request
    }
}

private extension ModelResponse {
    var finalText: String {
        outputText
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let values) = self {
            return values
        }
        return nil
    }
}
