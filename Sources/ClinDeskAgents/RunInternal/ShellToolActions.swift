import Foundation

extension RunnerLoop {
    func executeLocalShellToolRun(
        _ run: LocalShellToolRun<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> LocalShellRunResult {
        var span = await functionSpan(
            name: run.tool.name,
            input: config.traceIncludeSensitiveData ? run.call.action.prettyPrinted() : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        let hookContext = ToolHookContext(
            runContext: context,
            toolName: run.tool.name,
            toolCallID: run.call.callID,
            toolInput: run.call.action
        )
        do {
            try await callToolStartHooks(context: hookContext, agent: agent, tool: .localShell(run.tool))
        } catch {
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            throw error
        }
        do {
            let output = try await run.tool.executor(LocalShellCommandRequest(
                context: context,
                data: run.call
            ))
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .localShell(run.tool),
                output: output
            )
            await finishRunSpan(&span)
            return LocalShellRunResult(call: run.call, output: output)
        } catch {
            let output = String(describing: error)
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .localShell(run.tool),
                output: output
            )
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            return LocalShellRunResult(call: run.call, output: output)
        }
    }

    func executeShellToolRun(
        _ run: ShellToolRun<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> ShellRunResult {
        var span = await functionSpan(
            name: run.tool.name,
            input: config.traceIncludeSensitiveData ? shellActionInput(run.call.action) : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        let hookContext = ToolHookContext(
            runContext: context,
            toolName: run.tool.name,
            toolCallID: run.call.callID,
            toolInput: (try? JSONValue.encoded(run.call.action)) ?? .emptyObject
        )
        do {
            try await callToolStartHooks(context: hookContext, agent: agent, tool: .shell(run.tool))
        } catch {
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            throw error
        }

        do {
            let result = try await run.tool.executor(ShellCommandRequest(context: context, data: run.call))
            let normalized = normalizeShellToolOutput(result, action: run.call.action)
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? normalized.text : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .shell(run.tool),
                output: normalized.text
            )
            await finishRunSpan(&span)
            return ShellRunResult(call: run.call, output: normalized.output, status: normalized.status)
        } catch {
            let output = limitedShellOutput(String(describing: error), maxLength: run.call.action.maxOutputLength)
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(context: hookContext, agent: agent, tool: .shell(run.tool), output: output)
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            return ShellRunResult(
                call: run.call,
                output: .array([
                    shellCommandOutputJSON(ShellCommandOutput(
                        stdout: output,
                        outcome: ShellCallOutcome(type: .exit, exitCode: 1)
                    ))
                ]),
                status: "failed"
            )
        }
    }

    private func shellActionInput(_ action: ShellActionRequest) -> String {
        ((try? JSONValue.encoded(action)) ?? .emptyObject).prettyPrinted()
    }

    private func normalizeShellToolOutput(
        _ output: ShellToolOutput,
        action: ShellActionRequest
    ) -> (output: JSONValue, text: String, status: String) {
        switch output {
        case .text(let text):
            let limited = limitedShellOutput(text, maxLength: action.maxOutputLength)
            return (.string(limited), limited, "completed")
        case .result(let result):
            let maxLength = result.maxOutputLength ?? action.maxOutputLength
            let entries = result.output.map { shellCommandOutputJSON($0, maxLength: maxLength) }
            let text = limitedShellOutput(renderShellOutput(result.output), maxLength: maxLength)
            let failed = result.output.contains { entry in
                entry.outcome.type == .timeout || (entry.outcome.exitCode ?? 0) != 0
            }
            return (.array(entries), text, failed ? "failed" : "completed")
        }
    }

    private func shellCommandOutputJSON(
        _ output: ShellCommandOutput,
        maxLength: Int? = nil
    ) -> JSONValue {
        var outcome: [String: JSONValue] = [
            "type": .string(output.outcome.type.rawValue)
        ]
        if let exitCode = output.outcome.exitCode {
            outcome["exit_code"] = .number(Double(exitCode))
        }
        var payload: [String: JSONValue] = [
            "stdout": .string(limitedShellOutput(output.stdout, maxLength: maxLength)),
            "stderr": .string(limitedShellOutput(output.stderr, maxLength: maxLength)),
            "outcome": .object(outcome)
        ]
        if let providerData = output.providerData {
            payload["provider_data"] = .object(providerData)
        }
        return .object(payload)
    }

    private func renderShellOutput(_ outputs: [ShellCommandOutput]) -> String {
        outputs.map { output in
            var parts: [String] = []
            if let command = output.command {
                parts.append("$ \(command)")
            }
            if !output.stdout.isEmpty {
                parts.append(output.stdout)
            }
            if !output.stderr.isEmpty {
                parts.append("stderr:\n\(output.stderr)")
            }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func limitedShellOutput(_ output: String, maxLength: Int?) -> String {
        guard let maxLength, maxLength >= 0, output.count > maxLength else {
            return output
        }
        return String(output.prefix(maxLength))
    }
}
