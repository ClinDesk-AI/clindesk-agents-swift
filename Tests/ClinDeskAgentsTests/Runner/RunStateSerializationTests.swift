import Testing
import Foundation
import ClinDeskAgents

@Suite
struct RunStateSerializationTests {
    @Test
    func runStateToJSONUsesUpstreamSnapshotKeys() throws {
        let agent = Agent<Void>(name: "Assistant", modelName: "local-test")
        let functionCall = FunctionCall(
            id: "fc_123",
            callID: "call_123",
            name: "lookup",
            arguments: ["id": "acct_123"],
            toolOrigin: ToolOrigin(type: .function)
        )
        let approvalItem = ToolApprovalItem(
            toolName: "lookup",
            callID: "call_123",
            arguments: functionCall.arguments,
            tool: .function(ToolDescriptor(name: "lookup", description: "Lookup account.")),
            toolOrigin: ToolOrigin(type: .function)
        )
        let context = RunContext<Void>(
            usage: Usage(requests: 1, inputTokens: 2, outputTokens: 3, totalTokens: 5),
            approvals: [
                "lookup": ToolApprovalRecord(
                    rejected: ["call_123"],
                    rejectionMessages: ["call_123": "Denied."]
                )
            ]
        )
        let state = RunState(
            startingAgent: agent,
            currentAgent: agent,
            originalInput: [.message(AgentMessage(role: .user, content: "Find account"))],
            sessionInputItems: [.message(AgentMessage(role: .user, content: "Persist account lookup"))],
            modelInput: [.message(AgentMessage(role: .user, content: "Find account"))],
            newItems: [.functionCall(functionCall)],
            modelResponses: [
                ModelResponse(
                    output: [.functionCall(functionCall)],
                    usage: Usage(requests: 1, inputTokens: 2, outputTokens: 3, totalTokens: 5),
                    responseID: "resp_123",
                    requestID: "req_123"
                )
            ],
            runContext: context,
            trace: Trace(
                id: "trace_123",
                workflowName: "Workflow",
                groupID: "group_123",
                metadata: ["tenant": "clinic"]
            ),
            lastResponseID: "resp_123",
            currentTurn: 2,
            maxTurns: nil,
            interruptions: [approvalItem],
            pendingFunctionCalls: [functionCall],
            inputGuardrailResults: [
                InputGuardrailResult(
                    guardrailName: "input",
                    output: GuardrailFunctionOutput(outputInfo: "ok", tripwireTriggered: false)
                )
            ],
            toolInputGuardrailResults: [
                ToolInputGuardrailResult(
                    guardrailName: "tool_input",
                    toolName: "lookup",
                    callID: "call_123",
                    output: .rejectContent(message: "No.", outputInfo: "blocked")
                )
            ],
            toolOutputGuardrailResults: [],
            toolUseTrackerSnapshot: ["Assistant": ["lookup"]],
            generatedPromptCacheKey: "prompt_cache_123",
            config: RunConfig(),
            modelProvider: nil
        )

        let json = try state.toJSON(context: ["tenant": "clinic"])

        #expect(json["$schemaVersion"] == .string(runStateCurrentSchemaVersion))
        #expect(json["current_turn"] == .number(2))
        #expect(json["max_turns"] == .null)
        #expect(json["no_active_agent_run"] == .bool(true))
        #expect(json["current_agent"]?["name"] == .string("Assistant"))
        #expect(json["current_agent"]?["model"] == .string("local-test"))
        if case .array(let sessionInputItems)? = json["session_input_items"] {
            #expect(sessionInputItems.first?["content"] == .string("Persist account lookup"))
        } else {
            Issue.record("Expected serialized session input items.")
        }
        #expect(json["context"]?["context"]?["tenant"] == .string("clinic"))
        #expect(json["context"]?["usage"]?["requests"] == .number(1))
        #expect(json["context"]?["approvals"]?["lookup"]?["rejected"] == .array([.string("call_123")]))
        #expect(json["context"]?["approvals"]?["lookup"]?["rejection_messages"]?["call_123"] == .string("Denied."))
        #expect(json["previous_response_id"] == .string("resp_123"))
        #expect(json["generated_prompt_cache_key"] == .string("prompt_cache_123"))
        #expect(json["trace"]?["id"] == .string("trace_123"))
        #expect(json["trace"]?["workflow_name"] == .string("Workflow"))
        #expect(json["current_step"]?["type"] == .string("next_step_interruption"))

        if case .array(let modelResponses)? = json["model_responses"] {
            #expect(modelResponses.first?["response_id"] == .string("resp_123"))
            #expect(modelResponses.first?["request_id"] == .string("req_123"))
        } else {
            Issue.record("Expected serialized model responses.")
        }
        if case .array(let interruptions)? = json["current_step"]?["data"]?["interruptions"] {
            #expect(interruptions.first?["tool_name"] == .string("lookup"))
            #expect(interruptions.first?["call_id"] == .string("call_123"))
            #expect(interruptions.first?["tool"]?["type"] == .string("function"))
            #expect(interruptions.first?["tool_origin"]?["type"] == .string("function"))
        } else {
            Issue.record("Expected serialized interruptions.")
        }
        if case .array(let guardrails)? = json["tool_input_guardrail_results"] {
            #expect(guardrails.first?["output"]?["behavior"] == .string("reject_content"))
            #expect(guardrails.first?["output"]?["message"] == .string("No."))
        } else {
            Issue.record("Expected serialized tool guardrails.")
        }
    }

    @Test
    func runStateToStringProducesJSON() throws {
        let agent = Agent<Void>(name: "Assistant")
        let state = RunState(
            startingAgent: agent,
            currentAgent: agent,
            originalInput: [],
            modelInput: [],
            newItems: [],
            modelResponses: [],
            runContext: RunContext(),
            trace: .noOp(),
            lastResponseID: nil,
            currentTurn: 0,
            maxTurns: 10,
            interruptions: [],
            pendingFunctionCalls: [],
            inputGuardrailResults: [],
            toolInputGuardrailResults: [],
            toolOutputGuardrailResults: [],
            toolUseTrackerSnapshot: [:],
            config: RunConfig(),
            modelProvider: nil
        )

        let string = try state.toString()

        #expect(string.contains(#""$schemaVersion":"\#(runStateCurrentSchemaVersion)""#))
        #expect(string.contains(#""current_turn":0"#))
    }

    @Test
    func runStateRestoresFromJSONAndResumesApprovedToolCall() async throws {
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
        let state = try #require(interrupted.toState(as: Void.self))
        let snapshot = try state.toJSON()
        var restored = try RunState.fromJSON(snapshot, startingAgent: agent)

        #expect(restored.getInterruptions() == interrupted.interruptions)
        #expect(restored.pendingFunctionCalls.count == 1)
        #expect(restored.pendingFunctionCalls.first?.callID == "call_sensitive")
        #expect(restored.modelResponses.last?.responseID == interrupted.modelResponses.last?.responseID)

        restored.approve(try #require(restored.getInterruptions().first))
        let resumed = try await Runner.run(state: restored)

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
    func runStateRestoresFromJSONAndResumesApprovedCustomToolCall() async throws {
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
            needsApproval: { _ in true }
        ) { _, input in
            "edited: \(input)"
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let interrupted = try await Runner.run(agent: agent, input: "Run")
        let state = try #require(interrupted.toState(as: Void.self))
        let snapshot = try state.toJSON()
        var restored = try RunState.fromJSON(snapshot, startingAgent: agent)

        #expect(restored.getInterruptions() == interrupted.interruptions)
        #expect(restored.pendingCustomToolCalls.count == 1)
        #expect(restored.pendingCustomToolCalls.first?.callID == "call_custom")

        restored.approve(try #require(restored.getInterruptions().first))
        let resumed = try await Runner.run(state: restored)

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
    func runStateRestoresFromJSONAndResumesApprovedShellCall() async throws {
        let executor = RecordingRunStateShellExecutor()
        let shellCall = ShellCall(
            callID: "call_shell",
            action: ShellActionRequest(commands: ["echo hi"])
        )
        let model = FakeModel([
            ModelResponse(output: [.shellCall(shellCall)]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Shell approved."))
            ])
        ])
        let tool = try ShellTool<Void>(
            executor: executor.execute,
            needsApproval: .always
        )
        let agent = Agent<Void>(name: "sheller", tools: [.shell(tool)], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "run shell")
        let state = try #require(interrupted.toState(as: Void.self))
        let snapshot = try state.toString()
        var restored = try RunState.fromString(snapshot, startingAgent: agent)

        #expect(restored.getInterruptions() == interrupted.interruptions)
        #expect(restored.pendingShellCalls == [shellCall])
        #expect(await executor.calls.isEmpty)

        restored.approve(try #require(restored.getInterruptions().first))
        let resumed = try await Runner.run(state: restored)

        #expect(resumed.finalOutput == "Shell approved.")
        #expect(await executor.calls == [shellCall])
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains {
            if case .shellCallOutput(let output) = $0 {
                return output.callID == "call_shell"
                    && output.status == "completed"
                    && output.output == .string("shell ok")
            }
            return false
        } == true)
    }

    @Test
    func runStateRestoresFromJSONAndResumesApprovedApplyPatchCall() async throws {
        let editor = RecordingRunStateApplyPatchEditor()
        let patchCall = ApplyPatchCall(
            callID: "call_apply",
            operations: [
                ApplyPatchOperation(type: .updateFile, path: "tasks.md", diff: "-old\n+new\n")
            ]
        )
        let model = FakeModel([
            ModelResponse(output: [.applyPatchCall(patchCall)]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Patch approved."))
            ])
        ])
        let tool = ApplyPatchTool<Void>(
            editor: editor,
            needsApproval: .always
        )
        let agent = Agent<Void>(name: "patcher", tools: [.applyPatch(tool)], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "apply")
        let state = try #require(interrupted.toState(as: Void.self))
        let snapshot = try state.toJSON()
        var restored = try RunState.fromJSON(snapshot, startingAgent: agent)

        #expect(restored.getInterruptions() == interrupted.interruptions)
        #expect(restored.pendingApplyPatchCalls == [patchCall])
        #expect(editor.operations.isEmpty)

        restored.approve(try #require(restored.getInterruptions().first))
        let resumed = try await Runner.run(state: restored)

        #expect(resumed.finalOutput == "Patch approved.")
        #expect(editor.operations == patchCall.operations)
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains(ModelInputItem.applyPatchCallOutput(ApplyPatchCallOutput(
            callID: "call_apply",
            status: .completed,
            output: "Updated tasks.md"
        ))) == true)
    }
}

private actor RecordingRunStateShellExecutor {
    private var storedCalls: [ShellCall] = []

    var calls: [ShellCall] {
        storedCalls
    }

    func execute(_ request: ShellCommandRequest<Void>) async throws -> ShellToolOutput {
        storedCalls.append(request.data)
        return .text("shell ok")
    }
}

private final class RecordingRunStateApplyPatchEditor: ApplyPatchEditor, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOperations: [ApplyPatchOperation] = []

    var operations: [ApplyPatchOperation] {
        lock.withLock { storedOperations }
    }

    func createFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult? {
        record(operation)
        return ApplyPatchResult(status: .completed, output: "Created \(operation.path)")
    }

    func updateFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult? {
        record(operation)
        return ApplyPatchResult(status: .completed, output: "Updated \(operation.path)")
    }

    func deleteFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult? {
        record(operation)
        return ApplyPatchResult(status: .completed, output: "Deleted \(operation.path)")
    }

    private func record(_ operation: ApplyPatchOperation) {
        lock.withLock {
            storedOperations.append(operation)
        }
    }
}
