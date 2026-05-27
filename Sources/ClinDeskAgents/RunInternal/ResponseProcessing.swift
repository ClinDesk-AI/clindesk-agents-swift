extension RunnerLoop {
    func processModelResponse(
        _ response: ModelResponse,
        agent: Agent<Context>,
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        handoffs: [Handoff<Context>],
        functionToolLookupMap: [FunctionToolLookupKey: FunctionTool<Context>],
        customTools: [CustomTool<Context>],
        computerTools: [ComputerTool<Context>],
        localShellTools: [LocalShellTool<Context>],
        shellTools: [ShellTool<Context>],
        applyPatchTools: [ApplyPatchTool<Context>]
    ) async -> ProcessedModelResponse {
        let preHandoffItems = newItems
        let inputHistory: [ModelInputItem]
        if modelInput.count >= preHandoffItems.count {
            inputHistory = Array(modelInput.prefix(modelInput.count - preHandoffItems.count))
        } else {
            inputHistory = modelInput
        }

        let outputInputItems = Self.annotateFunctionToolOrigins(
            response.toInputItems(reasoningItemIDPolicy: config.reasoningItemIDPolicy),
            toolsByLookupKey: functionToolLookupMap
        )
        let handoffToolNames = Set(handoffs.map(\.descriptor.toolName))
        for outputItem in outputInputItems {
            await emitRunItemStreamEvent(RunnerStreaming.runItemStreamEvent(
                for: outputItem,
                agent: agent,
                handoffToolNames: handoffToolNames
            ))
        }

        let responseFunctionCalls = outputInputItems.compactMap { item -> FunctionCall? in
            if case .functionCall(let call) = item {
                return call
            }
            return nil
        }
        let handoffCalls = responseFunctionCalls.filter { call in
            handoffs.contains { $0.descriptor.toolName == call.name }
        }
        let toolCalls = responseFunctionCalls.filter { call in
            Self.functionTool(for: call, in: functionToolLookupMap) != nil
        }
        let unknownFunctionCalls = responseFunctionCalls.filter { call in
            Self.functionTool(for: call, in: functionToolLookupMap) == nil
                && !handoffs.contains { $0.descriptor.toolName == call.name }
        }
        let customToolCalls = response.customToolCalls.filter { call in
            customTools.contains { $0.descriptor.name == call.name }
        }
        let unknownCustomToolCalls = response.customToolCalls.filter { call in
            !customTools.contains { $0.descriptor.name == call.name }
        }
        let computerCalls = response.computerCalls.filter { _ in
            !computerTools.isEmpty
        }
        let unknownComputerCalls = response.computerCalls.filter { _ in
            computerTools.isEmpty
        }
        let localShellCalls = response.localShellCalls.filter { _ in
            !localShellTools.isEmpty
        }
        let unknownLocalShellCalls = response.localShellCalls.filter { _ in
            localShellTools.isEmpty
        }
        let shellCalls = response.shellCalls.filter { call in
            shellTools.contains { $0.descriptor.name == "shell" || $0.descriptor.name == call.raw?["name"]?.stringValue }
        }
        let unknownShellCalls = response.shellCalls.filter { _ in
            shellTools.isEmpty
        }
        let applyPatchCalls = response.applyPatchCalls.filter { _ in
            !applyPatchTools.isEmpty
        }
        let unknownApplyPatchCalls = response.applyPatchCalls.filter { _ in
            applyPatchTools.isEmpty
        }

        return ProcessedModelResponse(
            preHandoffItems: preHandoffItems,
            inputHistory: inputHistory,
            outputInputItems: outputInputItems,
            modelInput: modelInput + outputInputItems,
            newItems: newItems + outputInputItems,
            handoffCalls: handoffCalls,
            toolCalls: toolCalls,
            unknownFunctionCalls: unknownFunctionCalls,
            customToolCalls: customToolCalls,
            unknownCustomToolCalls: unknownCustomToolCalls,
            computerCalls: computerCalls,
            unknownComputerCalls: unknownComputerCalls,
            localShellCalls: localShellCalls,
            unknownLocalShellCalls: unknownLocalShellCalls,
            shellCalls: shellCalls,
            unknownShellCalls: unknownShellCalls,
            applyPatchCalls: applyPatchCalls,
            unknownApplyPatchCalls: unknownApplyPatchCalls
        )
    }
}
