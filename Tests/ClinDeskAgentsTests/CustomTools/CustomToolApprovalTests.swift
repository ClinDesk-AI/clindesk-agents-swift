import Testing
import ClinDeskAgents

@Suite
struct CustomToolApprovalTests {
    @Test
    func customToolApprovalCanInterruptAndResumeAfterApproval() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "draft"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Custom approved."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            format: ["type": "text"],
            needsApproval: { request in
                request.call.input == "draft"
            }
        ) { context, input in
            #expect(context.call.callID == "call_custom")
            return "edited: \(input)"
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let interrupted = try await Runner.run(agent: agent, input: "Run")

        #expect(interrupted.isInterrupted)
        let interruption = try #require(interrupted.interruptions.first)
        #expect(interruption.toolName == "raw_editor")
        #expect(interruption.callID == "call_custom")
        #expect(interruption.arguments == .string("draft"))
        #expect(interruption.tool == .custom(CustomToolDescriptor(
            name: "raw_editor",
            description: "Edit raw text.",
            format: ["type": "text"]
        )))

        var state = try #require(interrupted.state(as: Void.self))
        state.approve(interruption)

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Custom approved.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .customToolCallOutput(let output) = $0 {
                return output.callID == "call_custom" && output.output == "edited: draft"
            }
            return false
        } == true)
    }

    @Test
    func customToolApprovalRejectionFeedsModelVisibleOutputOnResume() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "draft"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Custom rejected."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            needsApproval: { _ in true }
        ) { _, _ in
            Issue.record("Rejected custom tool should not run")
            return "never"
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first), rejectionMessage: "Denied custom.")

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Custom rejected.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .customToolCallOutput(let output) = $0 {
                return output.callID == "call_custom" && output.output == "Denied custom."
            }
            return false
        } == true)
    }

    @Test
    func customToolApprovalDefaultRejectionMessageMirrorsUpstream() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "draft"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Custom rejected."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            needsApproval: { _ in true }
        ) { _, _ in
            Issue.record("Rejected custom tool should not run")
            return "never"
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        var state = try #require(interrupted.state(as: Void.self))
        state.reject(try #require(interrupted.interruptions.first))

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Custom rejected.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .customToolCallOutput(let output) = $0 {
                return output.callID == "call_custom" && output.output == defaultApprovalRejectionMessage
            }
            return false
        } == true)
    }

    @Test
    func customToolOnApprovalCanAutoApproveRequiredApproval() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "draft"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Auto approved."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            needsApproval: { _ in true },
            onApproval: { request in
                #expect(request.item.toolName == "raw_editor")
                #expect(request.item.callID == "call_custom")
                #expect(request.item.arguments == .string("draft"))
                return ToolApprovalDecision(approve: true)
            }
        ) { _, input in
            "auto: \(input)"
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(!result.isInterrupted)
        #expect(result.finalOutput == "Auto approved.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .customToolCallOutput(let output) = $0 {
                return output.callID == "call_custom" && output.output == "auto: draft"
            }
            return false
        } == true)
    }
}
