import Testing
import ClinDeskAgents

@Suite
struct TracingRunnerSpanTests {
    @Test
    func runnerEmitsTaskAgentTurnAndFunctionSpans() async throws {
        let processor = InMemoryTracingProcessor()
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_weather", name: "weather", arguments: ["city": "Cancun"]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Sunny."))
            ])
        ])
        let weather = FunctionTool<Void>(
            name: "weather",
            description: "Get weather.",
            parameters: ["type": "object"]
        ) { _, _ in
            .text("sunny")
        }
        let agent = Agent<Void>(name: "Weather", tools: [weather], model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Weather?",
            runConfig: RunConfig(workflowName: "Weather workflow", tracingProcessors: [processor])
        )

        let spans = await processor.endedSpans()
        let task = try #require(spans.first { spanKind($0) == "task" })
        let agentSpan = try #require(spans.first { spanKind($0) == "agent" })
        let turns = spans.filter { spanKind($0) == "turn" }
        let function = try #require(spans.first { spanKind($0) == "function" })

        #expect(agentSpan.parentID == task.spanID)
        #expect(turns.count == 2)
        #expect(turns.allSatisfy { $0.parentID == agentSpan.spanID })
        #expect(function.parentID == turns.first?.spanID)
        #expect(function.spanData.export()["name"] == "weather")
    }

    @Test
    func runnerEmitsHandoffSpanBetweenAgents() async throws {
        let processor = InMemoryTracingProcessor()
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Booking."))
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
            input: "Need an appointment",
            runConfig: RunConfig(workflowName: "Handoff workflow", tracingProcessors: [processor])
        )

        let spans = await processor.endedSpans()
        let handoff = try #require(spans.first { spanKind($0) == "handoff" })

        #expect(handoff.spanData.export()["from_agent"] == "Triage")
        #expect(handoff.spanData.export()["to_agent"] == "Booking")
        #expect(spans.filter { spanKind($0) == "agent" }.count == 2)
    }

    @Test
    func runnerEmitsGuardrailSpans() async throws {
        let processor = InMemoryTracingProcessor()
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Allowed."))
            ])
        ])
        let guardrail = InputGuardrail<Void>(name: "input_safety") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "ok", tripwireTriggered: false)
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            inputGuardrails: [guardrail]
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hello",
            runConfig: RunConfig(workflowName: "Guardrail workflow", tracingProcessors: [processor])
        )

        let guardrailSpan = try #require(await processor.endedSpans().first {
            spanKind($0) == "guardrail"
        })

        #expect(guardrailSpan.spanData.export()["name"] == "input_safety")
        #expect(guardrailSpan.spanData.export()["triggered"] == false)
    }

    @Test
    func taskAndTurnSpansUseUpstreamUsageShapes() async throws {
        let processor = InMemoryTracingProcessor()
        let model = FakeModel([
            ModelResponse(
                output: [.message(AgentMessage(role: .assistant, content: "Done."))],
                usage: Usage(
                    requests: 1,
                    inputTokens: 10,
                    inputTokensDetails: InputTokensDetails(cachedTokens: 4),
                    outputTokens: 3,
                    totalTokens: 13
                )
            )
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Hello",
            runConfig: RunConfig(tracingProcessors: [processor])
        )

        let spans = await processor.endedSpans()
        let task = try #require(spans.first { spanKind($0) == "task" })
        let turn = try #require(spans.first { spanKind($0) == "turn" })

        #expect(task.spanData.export()["data"]?["usage"] == [
            "input_tokens": 10,
            "output_tokens": 3,
            "cached_input_tokens": 4,
            "requests": 1,
            "total_tokens": 13
        ])
        #expect(turn.spanData.export()["data"]?["usage"] == [
            "input_tokens": 10,
            "output_tokens": 3,
            "cached_input_tokens": 4
        ])
    }

    @Test
    func failedToolSpanRedactsErrorDetailsWhenSensitiveDataIsDisabled() async throws {
        let processor = InMemoryTracingProcessor()
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_secret", name: "secret_tool", arguments: [:]))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "secret_tool",
            description: "Fails with a sensitive message.",
            failureErrorFunction: nil
        ) { _, _ in
            throw SecretToolError()
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        await #expect(throws: SecretToolError.self) {
            _ = try await Runner.run(
                agent: agent,
                input: "Run it",
                runConfig: RunConfig(
                    traceIncludeSensitiveData: false,
                    tracingProcessors: [processor]
                )
            )
        }

        let function = try #require(await processor.endedSpans().first { spanKind($0) == "function" })
        let error = try #require(function.error)

        #expect(error.message == "Error running tool")
        #expect(error.data?["tool_name"] == "secret_tool")
        #expect(error.data?["error"] == .string(ToolErrorUtils.redactedToolErrorMessage))
    }
}

private func spanKind(_ span: Span) -> String? {
    let exported = span.spanData.export()
    if exported["type"] == "custom" {
        return exported["name"]?.stringValue
    }
    return exported["type"]?.stringValue
}

private struct SecretToolError: Error, Equatable, CustomStringConvertible {
    var description: String {
        "sensitive patient detail"
    }
}
