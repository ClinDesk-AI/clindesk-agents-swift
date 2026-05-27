extension RunnerLoop {
    func executeHandoff(
        handoffCall: FunctionCall,
        handoffCalls: [FunctionCall],
        handoffs: [Handoff<Context>],
        currentAgent: Agent<Context>,
        runContext: RunContext<Context>,
        trace: inout Trace,
        resultInput: [ModelInputItem],
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        inputHistory: [ModelInputItem],
        preHandoffItems: [ModelInputItem],
        outputInputItems: [ModelInputItem],
        parentSpan: Span? = nil
    ) async throws -> HandoffTurnResolution<Context> {
        guard let handoff = handoffs.first(where: { $0.descriptor.toolName == handoffCall.name }) else {
            throw AgentsError.invalidModelResponse("Handoff call could not be resolved.")
        }

        var span = await handoffSpan(
            fromAgent: currentAgent.name,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)
        let nextAgent: Agent<Context>
        do {
            nextAgent = try await handoff.invoke(context: runContext, arguments: handoffCall.arguments)
            if var data = span.spanData as? HandoffSpanData {
                data.toAgent = nextAgent.name
                span.spanData = data
            }
            if handoffCalls.count > 1 {
                span.setError(SpanError(
                    message: "Multiple handoffs requested",
                    data: [
                        "requested_agents": .array(handoffCalls.map { .string($0.name) })
                    ]
                ))
            }
            await finishRunSpan(&span)
        } catch {
            await finishRunSpan(&span, error: error)
            throw error
        }
        var handoffOutputItems: [ModelInputItem] = handoffCalls.dropFirst().map { ignoredCall in
            .functionCallOutput(FunctionCallOutput(
                callID: ignoredCall.callID,
                output: .string("Multiple handoffs detected, ignoring this one.")
            ))
        }
        handoffOutputItems.append(.functionCallOutput(FunctionCallOutput(
            callID: handoffCall.callID,
            output: .string(handoff.transferMessage(for: nextAgent))
        )))

        var resolvedResultInput = resultInput
        var resolvedModelInput = modelInput + handoffOutputItems
        var resolvedNewItems = newItems + handoffOutputItems

        let selectedHandoffOutput = handoffOutputItems.last.flatMap { item -> FunctionCallOutput? in
            guard case .functionCallOutput(let output) = item else {
                return nil
            }
            return output
        }
        await emitRunItemStreamEvent(RunnerStreaming.handoffOutputEvent(
            from: currentAgent,
            to: nextAgent,
            output: selectedHandoffOutput
        ))

        try await callHandoffHooks(context: runContext, from: currentAgent, to: nextAgent)
        trace.items.append(.handoff(handoff.descriptor.toolName))

        let handoffInputData = HandoffInputData(
            inputHistory: inputHistory,
            preHandoffItems: preHandoffItems,
            newItems: outputInputItems + handoffOutputItems,
            runContext: runContext
        )
        if let inputFilter = handoff.inputFilter ?? config.handoffInputFilter {
            let filtered = try await inputFilter(handoffInputData)
            resolvedResultInput = filtered.inputHistory
            resolvedModelInput = filtered.modelInputItems
            resolvedNewItems = filtered.sessionItems
        } else if handoff.nestHandoffHistory ?? config.nestHandoffHistory {
            let nested = try await HandoffHistory.nestHandoffHistory(
                handoffInputData,
                historyMapper: config.handoffHistoryMapper
            )
            resolvedResultInput = nested.inputHistory
            resolvedModelInput = nested.modelInputItems
            resolvedNewItems = preHandoffItems + nested.newItems
        }

        return HandoffTurnResolution(
            agent: nextAgent,
            resultInput: resolvedResultInput,
            modelInput: resolvedModelInput,
            newItems: resolvedNewItems,
            shouldRunAgentStartHooks: true
        )
    }

    func resolveToolUseBehavior(
        _ behavior: ToolUseBehavior<Context>,
        context: RunContext<Context>,
        results: [ToolRunResult]
    ) async throws -> ToolUseResolution {
        switch behavior {
        case .runModelAgain:
            return .notFinal
        case .stopOnFirstTool:
            return ToolUseResolution(isFinalOutput: true, finalOutput: results.first?.output.finalOutputText ?? "")
        case .stopAtTools(let names):
            guard let result = results.first(where: {
                names.contains($0.call.name) || names.contains($0.call.qualifiedName)
            }) else {
                return .notFinal
            }
            return ToolUseResolution(isFinalOutput: true, finalOutput: result.output.finalOutputText)
        case .custom(let resolver):
            let result = try await resolver(context, results)
            guard result.isFinalOutput else {
                return .notFinal
            }
            return ToolUseResolution(isFinalOutput: true, finalOutput: result.finalOutput ?? "")
        }
    }

    static func functionTool(
        for call: FunctionCall,
        in lookupMap: [FunctionToolLookupKey: FunctionTool<Context>]
    ) -> FunctionTool<Context>? {
        guard let lookupKey = ToolIdentity.functionToolLookupKey(for: call) else {
            return nil
        }
        return lookupMap[lookupKey]
    }

    static func annotateFunctionToolOrigins(
        _ items: [ModelInputItem],
        toolsByLookupKey: [FunctionToolLookupKey: FunctionTool<Context>]
    ) -> [ModelInputItem] {
        items.map { item in
            guard case .functionCall(let call) = item,
                  let tool = functionTool(for: call, in: toolsByLookupKey)
            else {
                return item
            }
            return .functionCall(call.withToolOrigin(tool.resolvedToolOrigin))
        }
    }
}
