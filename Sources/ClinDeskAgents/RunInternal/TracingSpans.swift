import Foundation

extension RunnerLoop {
    func makeTaskSpan(trace: Trace) async -> Span {
        await taskSpan(
            name: trace.workflowName,
            parent: .trace(trace),
            disabled: config.tracingDisabled
        )
    }

    func makeAgentSpan(
        agent: Agent<Context>,
        tools: [Tool<Context>],
        handoffs: [Handoff<Context>],
        parent: Span
    ) async -> Span {
        await agentSpan(
            name: agent.name,
            handoffs: handoffs.map { $0.agent.name },
            tools: tools.compactMap(traceToolName),
            outputType: agent.outputSchema?.name ?? "str",
            parent: .span(parent),
            disabled: config.tracingDisabled
        )
    }

    func makeTurnSpan(turn: Int, agent: Agent<Context>, parent: Span) async -> Span {
        await turnSpan(
            turn: turn,
            agentName: agent.name,
            parent: .span(parent),
            disabled: config.tracingDisabled
        )
    }

    func makeGuardrailSpan(name: String, trace: Trace, parent: Span? = nil) async -> Span {
        if let parent {
            return await guardrailSpan(
                name: name,
                parent: .span(parent),
                disabled: config.tracingDisabled
            )
        }
        guard !config.tracingDisabled, !trace.isNoOp else {
            return .noOp(spanData: GuardrailSpanData(name: name))
        }
        return Span(
            spanData: GuardrailSpanData(name: name),
            traceID: trace.traceID,
            traceMetadata: trace.metadata
        )
    }

    func startRunSpan(_ span: inout Span) async {
        guard span.startedAt == nil else {
            return
        }
        await span.start()
        guard !config.tracingDisabled, !span.isNoOp else {
            return
        }
        for processor in config.tracingProcessors {
            await processor.onSpanStart(span)
        }
    }

    func finishRunSpan(_ span: inout Span, error: Error? = nil, toolName: String? = nil) async {
        guard span.endedAt == nil else {
            return
        }
        if let error {
            if let toolName {
                span.setError(SpanError(
                    message: "Error running tool",
                    data: [
                        "tool_name": .string(toolName),
                        "error": .string(ToolErrorUtils.traceToolError(
                            traceIncludeSensitiveData: config.traceIncludeSensitiveData,
                            errorMessage: String(describing: error)
                        ))
                    ]
                ))
            } else {
                span.setError(SpanError(message: String(describing: error)))
            }
        }
        await span.finish()
        guard !config.tracingDisabled, !span.isNoOp else {
            return
        }
        for processor in config.tracingProcessors {
            await processor.onSpanEnd(span)
        }
    }

    func attachUsageDelta(to span: inout Span, from start: Usage, to end: Usage) {
        let usage = usageDelta(from: start, to: end)
        if var data = span.spanData as? TaskSpanData {
            data.usage = usage.taskSpanUsage
            span.spanData = data
        } else if var data = span.spanData as? TurnSpanData {
            data.usage = usage.turnSpanUsage
            span.spanData = data
        }
    }

    func traceToolName(_ tool: Tool<Context>) -> String? {
        switch tool {
        case .function(let tool):
            return ToolIdentity.traceName(
                name: tool.descriptor.name,
                namespace: explicitNamespace(tool.descriptor.namespace)
            )
        case .custom(let tool):
            return ToolIdentity.traceName(name: tool.descriptor.name)
        case .computer:
            return "computer"
        case .localShell:
            return "local_shell"
        case .shell(let tool):
            return tool.name
        case .applyPatch(let tool):
            return tool.name
        }
    }

    func usageDelta(from start: Usage, to end: Usage) -> Usage {
        Usage(
            requests: max(0, end.requests - start.requests),
            inputTokens: max(0, end.inputTokens - start.inputTokens),
            inputTokensDetails: InputTokensDetails(
                cachedTokens: max(
                    0,
                    end.inputTokensDetails.cachedTokens - start.inputTokensDetails.cachedTokens
                )
            ),
            outputTokens: max(0, end.outputTokens - start.outputTokens),
            outputTokensDetails: OutputTokensDetails(
                reasoningTokens: max(
                    0,
                    end.outputTokensDetails.reasoningTokens - start.outputTokensDetails.reasoningTokens
                )
            ),
            totalTokens: max(0, end.totalTokens - start.totalTokens)
        )
    }

    private func explicitNamespace(_ namespace: String?) -> String? {
        guard let namespace, !namespace.isEmpty else {
            return nil
        }
        return namespace
    }
}
