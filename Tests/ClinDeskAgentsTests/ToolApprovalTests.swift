import Testing
import ClinDeskAgents

@Suite
struct ToolApprovalTests {
    @Test
    func toolApprovalCanInterruptAndResumeAfterApproval() async throws {
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

        let interrupted = try await Runner.run(agent: agent, input: "Run")

        #expect(interrupted.isInterrupted)
        #expect(interrupted.interruptions.first?.toolName == "sensitive")
        #expect(interrupted.interruptions.first?.callID == "call_sensitive")

        var state = try #require(interrupted.toState(as: Void.self))
        #expect(state.getInterruptions() == interrupted.interruptions)
        state.approve(try #require(state.getInterruptions().first))

        let resumed = try await Runner.run(state: state)
        #expect(resumed.finalOutput == "Approved.")

        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_sensitive" && output.output.stringValue == "ran"
            }
            return false
        } == true)
    }

    @Test
    func toolApprovalRejectionFeedsModelVisibleOutputOnResume() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Rejected."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first), rejectionMessage: "Denied by reviewer.")

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Rejected.")
        let requests = await model.requests()
        #expect(requests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_sensitive"
                    && output.output.stringValue == "Denied by reviewer."
            }
            return false
        } == true)
    }

    @Test
    func toolApprovalDefaultRejectionMessageMirrorsUpstream() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Rejected."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            Issue.record("Rejected tool should not run")
            return .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first))

        let resumed = try await Runner.run(state: state)

        #expect(defaultApprovalRejectionMessage == "Tool execution was not approved.")
        #expect(AgentsError.approvalRejected(toolName: "sensitive").localizedDescription == defaultApprovalRejectionMessage)
        #expect(resumed.finalOutput == "Rejected.")
        let requests = await model.requests()
        #expect(requests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_sensitive"
                    && output.output.stringValue == defaultApprovalRejectionMessage
            }
            return false
        } == true)
    }

    @Test
    func toolApprovalFormatterReceivesUpstreamDefaultRejectionMessage() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Rejected."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("never")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let interrupted = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(
                toolErrorFormatter: { args in
                    #expect(args.kind == .approvalRejected)
                    #expect(args.toolType == .function)
                    #expect(args.toolName == "sensitive")
                    #expect(args.callID == "call_sensitive")
                    #expect(args.defaultMessage == defaultApprovalRejectionMessage)
                    return "Approval denied by policy."
                }
            )
        )
        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first))

        _ = try await Runner.run(state: state)

        let requests = await model.requests()
        #expect(requests.last?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_sensitive"
                    && output.output.stringValue == "Approval denied by policy."
            }
            return false
        } == true)
    }
}
