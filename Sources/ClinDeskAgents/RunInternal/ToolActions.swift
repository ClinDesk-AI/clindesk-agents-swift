import Foundation

extension RunnerLoop {
    func executeToolCall(
        tool: FunctionTool<Context>,
        agent: Agent<Context>,
        context toolContext: ToolContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> ToolRunResult {
        let call = toolContext.call
        let toolName = ToolIdentity.traceName(
            name: tool.descriptor.name,
            namespace: explicitNamespace(tool.descriptor.namespace)
        ) ?? tool.descriptor.name
        var span = await functionSpan(
            name: toolName,
            input: config.traceIncludeSensitiveData ? call.arguments.prettyPrinted() : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        do {
            let result = try await executeToolCallBody(
                tool: tool,
                agent: agent,
                context: toolContext,
                parentSpan: span
            )
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? result.output.finalOutputText : nil
                span.spanData = data
            }
            await finishRunSpan(&span)
            return result
        } catch {
            await finishRunSpan(&span, error: error, toolName: toolName)
            throw error
        }
    }

    private func executeToolCallBody(
        tool: FunctionTool<Context>,
        agent: Agent<Context>,
        context toolContext: ToolContext<Context>,
        parentSpan: Span
    ) async throws -> ToolRunResult {
        let call = toolContext.call
        var inputGuardrailResults: [ToolInputGuardrailResult] = []
        for guardrail in tool.inputGuardrails {
            var span = await guardrailSpan(
                name: guardrail.name,
                parent: .span(parentSpan),
                disabled: config.tracingDisabled
            )
            await startRunSpan(&span)
            let output: ToolGuardrailFunctionOutput
            do {
                output = try await guardrail.run(context: toolContext)
                if var data = span.spanData as? GuardrailSpanData {
                    data.triggered = output.behavior == .raiseException
                    span.spanData = data
                }
                await finishRunSpan(&span)
            } catch {
                await finishRunSpan(&span, error: error)
                throw error
            }
            try await config.hooks.onGuardrail(guardrail.name, output.guardrailFunctionOutput)
            inputGuardrailResults.append(ToolInputGuardrailResult(
                guardrailName: guardrail.name,
                toolName: tool.descriptor.name,
                callID: call.callID,
                output: output
            ))
            switch output.behavior {
            case .allow:
                break
            case .rejectContent(let message):
                return ToolRunResult(
                    call: call,
                    output: .text(message),
                    inputGuardrailResults: inputGuardrailResults
                )
            case .raiseException:
                throw AgentsError.toolInputRejected(toolName: tool.descriptor.name, reason: output.outputInfo)
            }
        }

        let hookContext = ToolHookContext(toolContext: toolContext)
        try await callToolStartHooks(context: hookContext, agent: agent, tool: .function(tool))
        var output = try await tool.run(toolContext)
        if let nestedRunResult = await AgentToolState.peek(
            call: call,
            scopeID: toolContext.runContext.runID
        ), nestedRunResult.isInterrupted {
            return ToolRunResult(
                call: call,
                output: output,
                inputGuardrailResults: inputGuardrailResults,
                interruptions: nestedRunResult.interruptions
            )
        }

        var outputGuardrailResults: [ToolOutputGuardrailResult] = []
        for guardrail in tool.outputGuardrails {
            var span = await guardrailSpan(
                name: guardrail.name,
                parent: .span(parentSpan),
                disabled: config.tracingDisabled
            )
            await startRunSpan(&span)
            let result: ToolGuardrailFunctionOutput
            do {
                result = try await guardrail.run(context: toolContext, output: output)
                if var data = span.spanData as? GuardrailSpanData {
                    data.triggered = result.behavior == .raiseException
                    span.spanData = data
                }
                await finishRunSpan(&span)
            } catch {
                await finishRunSpan(&span, error: error)
                throw error
            }
            try await config.hooks.onGuardrail(guardrail.name, result.guardrailFunctionOutput)
            outputGuardrailResults.append(ToolOutputGuardrailResult(
                guardrailName: guardrail.name,
                toolName: tool.descriptor.name,
                callID: call.callID,
                output: result
            ))
            switch result.behavior {
            case .allow:
                break
            case .rejectContent(let message):
                output = .text(message)
                try await callToolEndHooks(
                    context: hookContext,
                    agent: agent,
                    tool: .function(tool),
                    output: output.finalOutputText
                )
                return ToolRunResult(
                    call: call,
                    output: output,
                    inputGuardrailResults: inputGuardrailResults,
                    outputGuardrailResults: outputGuardrailResults
                )
            case .raiseException:
                throw AgentsError.toolOutputRejected(toolName: tool.descriptor.name, reason: result.outputInfo)
            }
        }

        try await callToolEndHooks(
            context: hookContext,
            agent: agent,
            tool: .function(tool),
            output: output.finalOutputText
        )
        return ToolRunResult(
            call: call,
            output: output,
            inputGuardrailResults: inputGuardrailResults,
            outputGuardrailResults: outputGuardrailResults
        )
    }

    private func explicitNamespace(_ namespace: String?) -> String? {
        guard let namespace, !namespace.isEmpty else {
            return nil
        }
        return namespace
    }
}
