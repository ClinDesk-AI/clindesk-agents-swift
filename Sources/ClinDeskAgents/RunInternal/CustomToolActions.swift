import Foundation

extension RunnerLoop {
    func executeCustomToolRun(
        _ run: CustomToolRun<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> CustomToolRunResult {
        var span = await functionSpan(
            name: run.tool.name,
            input: config.traceIncludeSensitiveData ? run.call.input : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        do {
            let customContext = CustomToolContext(
                runContext: context,
                call: run.call,
                agent: agent.publicAgent,
                runConfig: config
            )
            let hookContext = ToolHookContext(customToolContext: customContext)
            try await callToolStartHooks(context: hookContext, agent: agent, tool: .custom(run.tool))
            let output = try await run.tool.run(customContext)
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? output : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .custom(run.tool),
                output: output
            )
            await finishRunSpan(&span)
            return CustomToolRunResult(call: run.call, output: output)
        } catch {
            await finishRunSpan(&span, error: error, toolName: run.tool.name)
            throw error
        }
    }
}
