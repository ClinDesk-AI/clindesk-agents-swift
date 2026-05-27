import Foundation

extension RunnerLoop {
    func executeApplyPatchToolRun(
        _ run: ApplyPatchToolRun<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> ApplyPatchRunResult {
        var span = await functionSpan(
            name: run.tool.name,
            input: config.traceIncludeSensitiveData ? applyPatchTraceInput(run.call.operations) : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        let hookContext = ToolHookContext(
            runContext: context,
            toolName: run.tool.name,
            toolCallID: run.call.callID,
            toolInput: applyPatchTracePayload(run.call.operations)
        )
        do {
            try await callToolStartHooks(context: hookContext, agent: agent, tool: .applyPatch(run.tool))
        } catch {
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            throw error
        }

        var status: ApplyPatchStatus = .completed
        var outputs: [String] = []
        do {
            for operation in run.call.operations {
                let result: ApplyPatchResult?
                switch operation.type {
                case .createFile:
                    result = try await run.tool.editor.createFile(operation)
                case .updateFile:
                    result = try await run.tool.editor.updateFile(operation)
                case .deleteFile:
                    result = try await run.tool.editor.deleteFile(operation)
                }
                if result?.status == .failed {
                    status = .failed
                }
                if let output = result?.output, !output.isEmpty {
                    outputs.append(output)
                }
            }
            let output = outputs.joined(separator: "\n")
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .applyPatch(run.tool),
                output: output
            )
            await finishRunSpan(&span)
            return ApplyPatchRunResult(call: run.call, status: status, output: output)
        } catch {
            let output = String(describing: error)
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .applyPatch(run.tool),
                output: output
            )
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            return ApplyPatchRunResult(call: run.call, status: .failed, output: output)
        }
    }

    private func applyPatchTraceInput(_ operations: [ApplyPatchOperation]) -> String {
        applyPatchTracePayload(operations).prettyPrinted()
    }

    private func applyPatchTracePayload(_ operations: [ApplyPatchOperation]) -> JSONValue {
        JSONValue.array(operations.map { operation in
            (try? JSONValue.encoded(operation)) ?? .emptyObject
        })
    }
}
