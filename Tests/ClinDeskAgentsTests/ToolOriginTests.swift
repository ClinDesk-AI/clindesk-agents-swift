import Testing
import ClinDeskAgents

@Suite
struct ToolOriginTests {
    @Test
    func toolOriginSerializesUsingUpstreamShape() throws {
        let origin = ToolOrigin(
            type: .agentAsTool,
            agentName: "Billing",
            agentToolName: "billing_agent"
        )

        let dictionary = origin.toDictionary()

        #expect(dictionary["type"] == .string("agent_as_tool"))
        #expect(dictionary["agent_name"] == .string("Billing"))
        #expect(dictionary["agent_tool_name"] == .string("billing_agent"))
        #expect(ToolOrigin(dictionary: dictionary) == origin)
        #expect(ToolOrigin(dictionary: ["type": .string("unknown")]) == nil)
    }

    @Test
    func runnerAttachesFunctionToolOriginToCallAndOutputItems() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "done"))
            ])
        ])
        let tool = FunctionTool<Void>(name: "lookup", description: "Lookup account.") { _, _ in
            .text("account")
        }
        let agent = Agent<Void>(name: "Tool Origin", tools: [tool], model: model)

        let result = try await Runner.run(agent: agent, input: "hello")

        let call = try #require(result.newItems.compactMap { item -> FunctionCall? in
            if case .functionCall(let call) = item {
                return call
            }
            return nil
        }.first)
        let output = try #require(result.newItems.compactMap { item -> FunctionCallOutput? in
            if case .functionCallOutput(let output) = item {
                return output
            }
            return nil
        }.first)

        #expect(call.toolOrigin == ToolOrigin(type: .function))
        #expect(output.toolOrigin == ToolOrigin(type: .function))
    }

    @Test
    func rejectedFunctionToolOutputPreservesToolOriginOnResume() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "rejected"))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Approval", tools: [tool], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "run")
        #expect(interrupted.interruptions.first?.toolOrigin == ToolOrigin(type: .function))

        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first), rejectionMessage: "Denied.")

        let resumed = try await Runner.run(state: state)
        let output = try #require(resumed.newItems.compactMap { item -> FunctionCallOutput? in
            if case .functionCallOutput(let output) = item {
                return output
            }
            return nil
        }.first)

        #expect(output.callID == "call_sensitive")
        #expect(output.output.stringValue == "Denied.")
        #expect(output.toolOrigin == ToolOrigin(type: .function))
    }

    @Test
    func agentAsToolUsesAgentToolOrigin() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "child answer"))
            ])
        ])
        let child = Agent<Void>(name: "Child Agent", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child_agent",
                    arguments: ["input": "help"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "done"))
            ])
        ])
        let parent = Agent<Void>(name: "Parent", tools: [child.asTool()], model: parentModel)

        let result = try await Runner.run(agent: parent, input: "run")
        let expected = ToolOrigin(
            type: .agentAsTool,
            agentName: "Child Agent",
            agentToolName: "child_agent"
        )
        let call = try #require(result.newItems.compactMap { item -> FunctionCall? in
            if case .functionCall(let call) = item {
                return call
            }
            return nil
        }.first)
        let output = try #require(result.newItems.compactMap { item -> FunctionCallOutput? in
            if case .functionCallOutput(let output) = item {
                return output
            }
            return nil
        }.first)

        #expect(call.toolOrigin == expected)
        #expect(output.toolOrigin == expected)
    }
}
