import Foundation

extension RunnerLoop {
    func runToolCalls(
        _ calls: [FunctionCall],
        tools: [FunctionTool<Context>],
        toolsByLookupKey: [FunctionToolLookupKey: FunctionTool<Context>],
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> ToolCallOutcome {
        let plan = try await planFunctionToolCalls(
            calls,
            tools: tools,
            toolsByLookupKey: toolsByLookupKey,
            context: context,
            trace: &trace
        )

        if plan.hasInterruptions {
            return .interrupted(plan.interruptions)
        }

        guard !plan.scheduled.isEmpty else {
            return .completed(plan.orderedResults(callCount: calls.count))
        }

        let maxConcurrency = min(
            config.toolExecution.maxFunctionToolConcurrency ?? plan.scheduled.count,
            plan.scheduled.count
        )
        var orderedResults = Array<ToolRunResult?>(repeating: nil, count: calls.count)

        return try await withThrowingTaskGroup(
            of: (Int, ToolRunResult, FunctionCallOutput).self
        ) { group in
            var nextIndex = 0

            func submitNext() {
                let run = plan.scheduled[nextIndex]
                nextIndex += 1
                group.addTask {
                    let toolContext = ToolContext(
                        runContext: context,
                        call: run.call,
                        agent: agent.publicAgent,
                        runConfig: config
                    )
                    let result = try await executeToolCall(
                        tool: run.tool,
                        agent: agent,
                        context: toolContext,
                        parentSpan: parentSpan
                    )
                    let output = ItemHelpers.toolCallOutputItem(toolCall: run.call, output: result.output)
                    return (run.offset, result, output)
                }
            }

            for _ in 0..<maxConcurrency {
                submitNext()
            }

            while let (offset, result, callOutput) = try await group.next() {
                orderedResults[offset] = result
                if result.interruptions.isEmpty {
                    trace.items.append(.toolResult(callOutput))
                }
                if nextIndex < plan.scheduled.count {
                    submitNext()
                }
            }

            var mergedResults = plan.immediateResults
            for (offset, result) in orderedResults.enumerated() {
                guard let result else { continue }
                mergedResults[offset] = result
            }
            let results = (0..<calls.count).compactMap { mergedResults[$0] }
            let nestedInterruptions = results.flatMap(\.interruptions)
            if !nestedInterruptions.isEmpty {
                return .interrupted(nestedInterruptions)
            }
            return .completed(results)
        }
    }

    func runCustomToolCalls(
        _ calls: [CustomToolCall],
        tools: [CustomTool<Context>],
        agent: Agent<Context>,
        context: inout RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> CustomToolCallOutcome {
        let plan = try await planCustomToolCalls(
            calls,
            tools: tools,
            context: &context,
            trace: &trace
        )
        if plan.hasInterruptions {
            return .interrupted(plan.interruptions)
        }

        var mergedResults = plan.immediateResults
        for offset in 0..<calls.count {
            guard let result = plan.immediateResults[offset] else { continue }
            trace.items.append(.customToolResult(CustomToolCallOutput(
                callID: result.call.callID,
                output: result.output
            )))
        }
        for run in plan.scheduled {
            let result = try await executeCustomToolRun(
                run,
                agent: agent,
                context: context,
                parentSpan: parentSpan
            )
            let callOutput = CustomToolCallOutput(callID: result.call.callID, output: result.output)
            trace.items.append(.customToolResult(callOutput))
            mergedResults[run.offset] = result
        }
        let results = (0..<calls.count).compactMap { mergedResults[$0] }
        return .completed(results)
    }

    func runComputerCalls(
        _ calls: [ComputerCall],
        tools: [ComputerTool<Context>],
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> ComputerToolCallOutcome {
        let plan = try planComputerCalls(calls, tools: tools, trace: &trace)
        var mergedResults: [Int: ComputerRunResult] = [:]
        for run in plan.scheduled {
            let result = try await executeComputerToolRun(
                run,
                agent: agent,
                context: context,
                parentSpan: parentSpan
            )
            let callOutput = ComputerCallOutput(
                callID: result.call.callID,
                output: [
                    "type": "computer_screenshot",
                    "image_url": .string(result.imageURL)
                ],
                acknowledgedSafetyChecks: result.acknowledgedSafetyChecks
            )
            trace.items.append(.computerResult(callOutput))
            mergedResults[run.offset] = result
        }
        let results = (0..<calls.count).compactMap { mergedResults[$0] }
        return .completed(results)
    }

    func runLocalShellCalls(
        _ calls: [LocalShellCall],
        tools: [LocalShellTool<Context>],
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> LocalShellToolCallOutcome {
        let plan = try planLocalShellCalls(calls, tools: tools, trace: &trace)
        var mergedResults: [Int: LocalShellRunResult] = [:]
        for run in plan.scheduled {
            let result = try await executeLocalShellToolRun(
                run,
                agent: agent,
                context: context,
                parentSpan: parentSpan
            )
            let callOutput = LocalShellCallOutput(callID: result.call.callID, output: result.output)
            trace.items.append(.localShellResult(callOutput))
            mergedResults[run.offset] = result
        }
        let results = (0..<calls.count).compactMap { mergedResults[$0] }
        return .completed(results)
    }

    func runShellCalls(
        _ calls: [ShellCall],
        tools: [ShellTool<Context>],
        agent: Agent<Context>,
        context: inout RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> ShellToolCallOutcome {
        let plan = try await planShellCalls(calls, tools: tools, context: &context, trace: &trace)
        if plan.hasInterruptions {
            return .interrupted(plan.interruptions)
        }

        var mergedResults = plan.immediateResults
        for offset in 0..<calls.count {
            guard let result = plan.immediateResults[offset] else { continue }
            trace.items.append(.shellResult(ShellCallOutput(
                callID: result.call.callID,
                output: result.output,
                status: result.status
            )))
        }
        for run in plan.scheduled {
            let result = try await executeShellToolRun(
                run,
                agent: agent,
                context: context,
                parentSpan: parentSpan
            )
            let callOutput = ShellCallOutput(
                callID: result.call.callID,
                output: result.output,
                status: result.status
            )
            trace.items.append(.shellResult(callOutput))
            mergedResults[run.offset] = result
        }
        let results = (0..<calls.count).compactMap { mergedResults[$0] }
        return .completed(results)
    }

    func runApplyPatchCalls(
        _ calls: [ApplyPatchCall],
        tools: [ApplyPatchTool<Context>],
        agent: Agent<Context>,
        context: inout RunContext<Context>,
        trace: inout Trace,
        parentSpan: Span? = nil
    ) async throws -> ApplyPatchToolCallOutcome {
        let plan = try await planApplyPatchCalls(calls, tools: tools, context: &context, trace: &trace)
        if plan.hasInterruptions {
            return .interrupted(plan.interruptions)
        }

        var mergedResults = plan.immediateResults
        for offset in 0..<calls.count {
            guard let result = plan.immediateResults[offset] else { continue }
            trace.items.append(.applyPatchResult(ApplyPatchCallOutput(
                callID: result.call.callID,
                status: result.status,
                output: result.output
            )))
        }
        for run in plan.scheduled {
            let result = try await executeApplyPatchToolRun(
                run,
                agent: agent,
                context: context,
                parentSpan: parentSpan
            )
            let callOutput = ApplyPatchCallOutput(
                callID: result.call.callID,
                status: result.status,
                output: result.output
            )
            trace.items.append(.applyPatchResult(callOutput))
            mergedResults[run.offset] = result
        }
        let results = (0..<calls.count).compactMap { mergedResults[$0] }
        return .completed(results)
    }
}
