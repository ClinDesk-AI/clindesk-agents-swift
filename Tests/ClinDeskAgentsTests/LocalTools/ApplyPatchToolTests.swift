import Foundation
import Testing
import ClinDeskAgents

private final class RecordingApplyPatchEditor: ApplyPatchEditor, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOperations: [ApplyPatchOperation] = []
    var failUpdates = false

    var operations: [ApplyPatchOperation] {
        lock.withLock { storedOperations }
    }

    func createFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult? {
        record(operation)
        return ApplyPatchResult(status: .completed, output: "Created \(operation.path)")
    }

    func updateFile(_ operation: ApplyPatchOperation) async throws -> ApplyPatchResult? {
        record(operation)
        if failUpdates {
            return ApplyPatchResult(status: .failed, output: "Failed \(operation.path)")
        }
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

@Suite
struct ApplyPatchToolTests {
    @Test
    func runnerExecutesApplyPatchCallsAndFeedsOutputBackToModel() async throws {
        let editor = RecordingApplyPatchEditor()
        let patchCall = ApplyPatchCall(
            id: "apc_123",
            callID: "call_apply",
            operations: [
                ApplyPatchOperation(type: .updateFile, path: "tasks.md", diff: "-old\n+new\n")
            ],
            status: "completed"
        )
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "patching")),
                .applyPatchCall(patchCall)
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "patch complete"))
            ])
        ])
        let tool = ApplyPatchTool<Void>(editor: editor)
        let agent = Agent<Void>(
            name: "patcher",
            tools: [.applyPatch(tool)],
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "update tasks")

        #expect(result.finalOutput == "patch complete")
        #expect(editor.operations == patchCall.operations)
        let output = ApplyPatchCallOutput(
            callID: "call_apply",
            status: .completed,
            output: "Updated tasks.md"
        )
        #expect(result.newItems.contains(ModelInputItem.applyPatchCall(patchCall)))
        #expect(result.newItems.contains(ModelInputItem.applyPatchCallOutput(output)))

        let secondInput = try #require(await model.requests().last?.input)
        #expect(secondInput.contains(ModelInputItem.applyPatchCallOutput(output)))
    }

    @Test
    func failedApplyPatchOperationKeepsOverallFailedStatus() async throws {
        let editor = RecordingApplyPatchEditor()
        editor.failUpdates = true
        let patchCall = ApplyPatchCall(
            callID: "call_multi",
            operations: [
                ApplyPatchOperation(type: .updateFile, path: "a.md", diff: "-x\n+y\n"),
                ApplyPatchOperation(type: .createFile, path: "b.md", diff: "+hi\n")
            ]
        )
        let model = FakeModel([
            ModelResponse(output: [.applyPatchCall(patchCall)]),
            ModelResponse(output: [.message(AgentMessage(role: .assistant, content: "done"))])
        ])
        let tool = ApplyPatchTool<Void>(editor: editor)
        let agent = Agent<Void>(name: "patcher", tools: [.applyPatch(tool)], model: model)

        let result = try await Runner.run(agent: agent, input: "apply")

        #expect(result.finalOutput == "done")
        #expect(editor.operations == patchCall.operations)
        #expect(result.newItems.contains(ModelInputItem.applyPatchCallOutput(ApplyPatchCallOutput(
            callID: "call_multi",
            status: .failed,
            output: "Failed a.md\nCreated b.md"
        ))))
    }

    @Test
    func applyPatchApprovalRejectionFeedsModelVisibleOutputOnResume() async throws {
        let editor = RecordingApplyPatchEditor()
        let patchCall = ApplyPatchCall(
            callID: "call_apply",
            operations: [
                ApplyPatchOperation(type: .updateFile, path: "tasks.md", diff: "-old\n+new\n")
            ]
        )
        let model = FakeModel([
            ModelResponse(output: [.applyPatchCall(patchCall)]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Patch rejected."))
            ])
        ])
        let tool = ApplyPatchTool<Void>(
            editor: editor,
            needsApproval: .always
        )
        let agent = Agent<Void>(name: "patcher", tools: [.applyPatch(tool)], model: model)

        let interrupted = try await Runner.run(agent: agent, input: "apply")

        #expect(interrupted.isInterrupted)
        let interruption = try #require(interrupted.interruptions.first)
        #expect(interruption.toolName == "apply_patch")
        #expect(interruption.callID == "call_apply")
        #expect(interruption.arguments == .array(
            patchCall.operations.map { (try? JSONValue.encoded($0)) ?? .emptyObject }
        ))
        #expect(editor.operations.isEmpty)

        var state = try #require(interrupted.state(as: Void.self))
        state.reject(interruption, rejectionMessage: "Denied patch.")

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Patch rejected.")
        #expect(editor.operations.isEmpty)
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.last?.input.contains(ModelInputItem.applyPatchCallOutput(ApplyPatchCallOutput(
            callID: "call_apply",
            status: .failed,
            output: "Denied patch."
        ))) == true)
    }
}
