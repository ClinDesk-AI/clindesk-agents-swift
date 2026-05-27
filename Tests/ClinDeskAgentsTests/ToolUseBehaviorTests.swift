import Testing
import ClinDeskAgents

@Suite
struct ToolUseBehaviorTests {
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
    func customToolUseBehaviorFinalNilDoesNotFallBackToToolOutput() async throws {
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
            toolUseBehavior: .custom { _, _ in
                ToolsToFinalOutputResult(isFinalOutput: true, finalOutput: nil)
            }
        )

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "")
    }
}
