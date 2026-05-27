import Foundation

extension RunnerLoop {
    private struct InputGuardrailRunResult: Sendable {
        var name: String
        var output: GuardrailFunctionOutput

        var result: InputGuardrailResult {
            InputGuardrailResult(guardrailName: name, output: output)
        }
    }

    private struct OutputGuardrailRunResult: Sendable {
        var name: String
        var agentName: String
        var agentOutput: String
        var output: GuardrailFunctionOutput

        var result: OutputGuardrailResult {
            OutputGuardrailResult(
                guardrailName: name,
                agentName: agentName,
                agentOutput: agentOutput,
                output: output
            )
        }
    }

    func runInputGuardrails(
        agent: Agent<Context>,
        context: RunContext<Context>,
        input: [ModelInputItem],
        trace: inout Trace
    ) async throws -> [InputGuardrailResult] {
        var results: [InputGuardrailResult] = []
        let guardrails = configInputGuardrails(for: agent)
        let sequentialGuardrails = guardrails.filter { !$0.runInParallel }
        let parallelGuardrails = guardrails.filter(\.runInParallel)

        for guardrail in sequentialGuardrails {
            let runResult = try await runSingleInputGuardrail(
                guardrail,
                agent: agent,
                context: context,
                input: input,
                trace: trace
            )
            try await config.hooks.onGuardrail(runResult.name, runResult.output)
            results.append(runResult.result)
            if runResult.output.tripwireTriggered {
                trace.items.append(.guardrail(runResult.name))
                throw AgentsError.inputGuardrailTripwire(
                    name: runResult.name,
                    reason: runResult.output.outputInfo
                )
            }
        }

        let traceSnapshot = trace
        try await withThrowingTaskGroup(of: InputGuardrailRunResult.self) { group in
            for guardrail in parallelGuardrails {
                group.addTask {
                    try await runSingleInputGuardrail(
                        guardrail,
                        agent: agent,
                        context: context,
                        input: input,
                        trace: traceSnapshot
                    )
                }
            }

            while let runResult = try await group.next() {
                try await config.hooks.onGuardrail(runResult.name, runResult.output)
                results.append(runResult.result)
                if runResult.output.tripwireTriggered {
                    group.cancelAll()
                    trace.items.append(.guardrail(runResult.name))
                    throw AgentsError.inputGuardrailTripwire(
                        name: runResult.name,
                        reason: runResult.output.outputInfo
                    )
                }
            }
        }

        return results
    }

    func runOutputGuardrails(
        agent: Agent<Context>,
        context: RunContext<Context>,
        output: String,
        trace: inout Trace
    ) async throws -> [OutputGuardrailResult] {
        var results: [OutputGuardrailResult] = []
        let traceSnapshot = trace

        try await withThrowingTaskGroup(of: OutputGuardrailRunResult.self) { group in
            for guardrail in agent.outputGuardrails + config.outputGuardrails {
                group.addTask {
                    try await runSingleOutputGuardrail(
                        guardrail,
                        agent: agent,
                        context: context,
                        output: output,
                        trace: traceSnapshot
                    )
                }
            }

            while let runResult = try await group.next() {
                try await config.hooks.onGuardrail(runResult.name, runResult.output)
                results.append(runResult.result)
                if runResult.output.tripwireTriggered {
                    group.cancelAll()
                    trace.items.append(.guardrail(runResult.name))
                    throw AgentsError.outputGuardrailTripwire(
                        name: runResult.name,
                        reason: runResult.output.outputInfo
                    )
                }
            }
        }

        return results
    }

    func configInputGuardrails(for agent: Agent<Context>) -> [InputGuardrail<Context>] {
        agent.inputGuardrails + config.inputGuardrails
    }

    private func runSingleInputGuardrail(
        _ guardrail: InputGuardrail<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        input: [ModelInputItem],
        trace: Trace
    ) async throws -> InputGuardrailRunResult {
        var span = await makeGuardrailSpan(name: guardrail.name, trace: trace)
        await startRunSpan(&span)
        let output: GuardrailFunctionOutput
        do {
            output = try await guardrail.run(context: context, agent: agent.publicAgent, input: input)
            if var data = span.spanData as? GuardrailSpanData {
                data.triggered = output.tripwireTriggered
                span.spanData = data
            }
            await finishRunSpan(&span)
        } catch {
            await finishRunSpan(&span, error: error)
            throw error
        }

        return InputGuardrailRunResult(name: guardrail.name, output: output)
    }

    private func runSingleOutputGuardrail(
        _ guardrail: OutputGuardrail<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        output: String,
        trace: Trace
    ) async throws -> OutputGuardrailRunResult {
        var span = await makeGuardrailSpan(name: guardrail.name, trace: trace)
        await startRunSpan(&span)
        let result: GuardrailFunctionOutput
        let publicAgent = agent.publicAgent
        do {
            result = try await guardrail.run(context: context, agent: publicAgent, output: output)
            if var data = span.spanData as? GuardrailSpanData {
                data.triggered = result.tripwireTriggered
                span.spanData = data
            }
            await finishRunSpan(&span)
        } catch {
            await finishRunSpan(&span, error: error)
            throw error
        }

        return OutputGuardrailRunResult(
            name: guardrail.name,
            agentName: publicAgent.name,
            agentOutput: output,
            output: result
        )
    }
}
