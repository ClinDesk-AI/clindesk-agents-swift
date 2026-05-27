import Foundation

extension RunnerLoop {
    func handleModelRefusal(
        _ refusal: String,
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        resultInput: [ModelInputItem],
        sessionInputItems: [ModelInputItem],
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        responseID: String?,
        inputGuardrailResults: [InputGuardrailResult],
        toolInputGuardrailResults: [ToolInputGuardrailResult],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    ) async throws -> RunResult {
        let error = AgentsError.modelRefusal(refusal)
        guard let handler = config.errorHandlers?.modelRefusal,
              let result = try await handler(RunErrorHandlerInput(
                error: error,
                context: context,
                runData: buildRunErrorData(
                    agent: agent,
                    resultInput: resultInput,
                    newItems: newItems,
                    modelResponses: modelResponses,
                    inputGuardrailResults: inputGuardrailResults
                )
              ))
        else {
            if let session = config.session {
                try await session.addItems(sessionInputItems + newItems)
            }
            throw error
        }

        var finalItems = newItems
        var finalModelInput = modelInput
        if result.includeInHistory {
            let message = ModelInputItem.message(AgentMessage(role: .assistant, content: result.finalOutput))
            finalItems.append(message)
            finalModelInput.append(message)
        }
        return try await finish(
            result.finalOutput,
            agent: agent,
            context: context,
            trace: &trace,
            resultInput: resultInput,
            sessionInputItems: sessionInputItems,
            modelInput: finalModelInput,
            newItems: finalItems,
            modelResponses: modelResponses,
            responseID: responseID,
            inputGuardrailResults: inputGuardrailResults,
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults
        )
    }

    func handleMaxTurnsExceeded(
        maxTurns: Int,
        agent: Agent<Context>,
        context: RunContext<Context>,
        trace: inout Trace,
        resultInput: [ModelInputItem],
        sessionInputItems: [ModelInputItem],
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        responseID: String?,
        inputGuardrailResults: [InputGuardrailResult],
        toolInputGuardrailResults: [ToolInputGuardrailResult],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    ) async throws -> RunResult {
        let error = AgentsError.maxTurnsExceeded(maxTurns)
        guard let handler = config.errorHandlers?.maxTurns,
              let result = try await handler(RunErrorHandlerInput(
                error: error,
                context: context,
                runData: buildRunErrorData(
                    agent: agent,
                    resultInput: resultInput,
                    newItems: newItems,
                    modelResponses: modelResponses,
                    inputGuardrailResults: inputGuardrailResults
                )
              ))
        else {
            if let session = config.session {
                try await session.addItems(sessionInputItems + newItems)
            }
            throw error
        }

        var finalItems = newItems
        var finalModelInput = modelInput
        if result.includeInHistory {
            let message = ModelInputItem.message(AgentMessage(role: .assistant, content: result.finalOutput))
            finalItems.append(message)
            finalModelInput.append(message)
        }
        return try await finish(
            result.finalOutput,
            agent: agent,
            context: context,
            trace: &trace,
            resultInput: resultInput,
            sessionInputItems: sessionInputItems,
            modelInput: finalModelInput,
            newItems: finalItems,
            modelResponses: modelResponses,
            responseID: responseID,
            inputGuardrailResults: inputGuardrailResults,
            toolInputGuardrailResults: toolInputGuardrailResults,
            toolOutputGuardrailResults: toolOutputGuardrailResults
        )
    }

    func buildRunErrorData(
        agent: Agent<Context>,
        resultInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        inputGuardrailResults: [InputGuardrailResult] = [],
        outputGuardrailResults: [OutputGuardrailResult] = []
    ) -> RunErrorData<Context> {
        let publicAgent = agent.publicAgent
        return RunErrorData(
            input: resultInput,
            newItems: newItems,
            history: resultInput + newItems,
            output: newItems,
            modelResponses: modelResponses,
            lastAgent: publicAgent,
            inputGuardrailResults: inputGuardrailResults,
            outputGuardrailResults: outputGuardrailResults
        )
    }

    func resolveToolNotFoundMessage(
        toolName: String,
        callID: String,
        context: RunContext<Context>
    ) async -> String {
        let defaultMessage = "Tool '\(toolName)' not found."
        guard let formatter = config.toolErrorFormatter else {
            return defaultMessage
        }
        do {
            return try await formatter(ToolErrorFormatterArgs(
                kind: .toolNotFound,
                toolType: .function,
                toolName: toolName,
                callID: callID,
                defaultMessage: defaultMessage,
                runContext: context
            )) ?? defaultMessage
        } catch {
            return defaultMessage
        }
    }

    func resolveApprovalRejectedMessage(
        toolName: String,
        callID: String,
        context: RunContext<Context>,
        toolType: ToolErrorFormatterArgs<Context>.ToolType = .function
    ) async -> String {
        let defaultMessage = defaultApprovalRejectionMessage
        guard let formatter = config.toolErrorFormatter else {
            return defaultMessage
        }
        do {
            return try await formatter(ToolErrorFormatterArgs(
                kind: .approvalRejected,
                toolType: toolType,
                toolName: toolName,
                callID: callID,
                defaultMessage: defaultMessage,
                runContext: context
            )) ?? defaultMessage
        } catch {
            return defaultMessage
        }
    }
}
