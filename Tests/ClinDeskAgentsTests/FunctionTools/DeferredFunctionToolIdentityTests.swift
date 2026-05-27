import Testing
import ClinDeskAgents

@Suite
struct DeferredFunctionToolIdentityTests {
    @Test
    func runnerRejectsDuplicateDeferredTopLevelFunctionTools() async throws {
        let first = FunctionTool<Void>(
            name: "search",
            description: "Search A.",
            deferLoading: true
        ) { _, _ in
            .text("a")
        }
        let second = FunctionTool<Void>(
            name: "search",
            description: "Search B.",
            deferLoading: true
        ) { _, _ in
            .text("b")
        }
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Should not call model."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.function(first), .function(second)],
            model: model
        )

        await #expect(throws: AgentsError.invalidRunConfig(
            "Ambiguous function tool configuration: the deferred top-level tool name `search` is used by multiple tools. Rename one of the deferred-loading top-level function tools to avoid ambiguous dispatch."
        )) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }

        #expect(await model.requests().isEmpty)
    }

    @Test
    func deferredTopLevelApprovalInterruptionPreservesSyntheticLookupMetadata() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_weather",
                    name: "get_weather",
                    namespace: "get_weather",
                    arguments: [:]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Approved."))
            ])
        ])
        let weather = FunctionTool<Void>(
            name: "get_weather",
            description: "Get weather.",
            deferLoading: true,
            approval: { _ in true }
        ) { _, _ in
            .text("sunny")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [weather], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "Run")

        let interruption = try #require(interrupted.interruptions.first)
        #expect(interruption.toolName == "get_weather")
        #expect(interruption.toolNamespace == "get_weather")
        #expect(interruption.toolLookupKey == .deferredTopLevel("get_weather"))
        #expect(interruption.allowBareNameAlias)

        var state = try #require(interrupted.state(as: Void.self))
        state.approve(interruption)
        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Approved.")
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_weather"
                    && output.output.stringValue == "sunny"
            }
            return false
        } == true)
    }
}
