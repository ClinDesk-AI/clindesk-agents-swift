import Testing
import ClinDeskAgents

@Suite
struct AgentToolOutputExtractionTests {
    @Test
    func agentAsToolCanUseCustomOutputExtractor() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(customOutputExtractor: { result in
                    "custom: \(result.finalOutput)"
                })
            ],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let parentRequests = await parentModel.requests()
        #expect(parentRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_child"
                    && output.output.stringValue == "custom: Child answer."
            }
            return false
        } == true)
    }

    @Test
    func agentAsToolFallsBackToLatestNestedRunOutputWhenFinalOutputIsEmpty() async throws {
        let lookup = FunctionTool<Void>(name: "lookup", description: "Lookup.") { _, _ in
            .text("Current run summary")
        }
        let childModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: ""))
            ])
        ])
        let child = Agent<Void>(name: "Child", tools: [lookup], model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool()],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let parentRequests = await parentModel.requests()
        #expect(parentRequests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_child"
                    && output.output.stringValue == "Current run summary"
            }
            return false
        } == true)
    }

    @Test
    func agentAsToolExposesInvocationMetadataToCustomOutputExtractor() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer.", "priority": "high"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(customOutputExtractor: { result in
                    #expect(result.agentToolInvocation == AgentToolInvocation(
                        toolName: "child",
                        toolCallID: "call_child",
                        toolArguments: ["input": "Need a child answer.", "priority": "high"]
                    ))
                    return result.finalOutput
                })
            ],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")
    }
}
