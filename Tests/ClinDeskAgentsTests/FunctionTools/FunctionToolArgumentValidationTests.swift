import Testing
import ClinDeskAgents

@Suite
struct FunctionToolArgumentValidationTests {
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
            parameters: ["type": "object"],
            failureErrorFunction: nil
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
    func strictFunctionToolSchemaFailsBeforeModelRequestWhenInvalid() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "unused"))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "lookup",
            description: "Lookup.",
            parameters: [
                "type": "object",
                "additionalProperties": true
            ]
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        do {
            _ = try await Runner.run(agent: agent, input: "Run")
            Issue.record("Expected invalid strict schema")
        } catch AgentsError.invalidRunConfig(let message) {
            #expect(message.contains("Invalid strict JSON schema for function tool 'lookup'"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await model.requests().isEmpty)
    }
}
