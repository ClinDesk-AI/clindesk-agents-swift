import Foundation

public typealias AgentToolOutputExtractor = @Sendable (RunResult) async throws -> String

public extension Agent {
    func asTool(
        name: String? = nil,
        description: String? = nil,
        customOutputExtractor: AgentToolOutputExtractor? = nil,
        isEnabled: @escaping FunctionTool<Context>.Enabled = { _ in true },
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context>? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        onStream: AgentToolStreamHandler<Context>? = nil,
        session: (any Session)? = nil,
        failureErrorFunction: ToolErrorFunction<Context>? = FunctionTool.defaultFailureErrorFunction,
        approval: FunctionTool<Context>.Approval? = nil,
        parameters: JSONValue? = nil,
        inputBuilder: StructuredToolInputBuilder? = nil,
        includeInputSchema: Bool = false
    ) -> FunctionTool<Context> {
        let toolName = name ?? Self.defaultToolName(for: self.name)
        let hasCustomParameters = parameters != nil
        let includeSchema = includeInputSchema && hasCustomParameters
        let parameterSchema = parameters ?? AgentToolInputHelpers.defaultInputSchema
        let shouldCaptureStructuredInput = hasCustomParameters || inputBuilder != nil
        let schemaInfo = AgentToolInputHelpers.buildStructuredInputSchemaInfo(
            parameters: parameterSchema,
            includeJSONSchema: includeSchema
        )
        return FunctionTool(
            name: toolName,
            description: description ?? "",
            parameters: parameterSchema,
            failureErrorFunction: failureErrorFunction,
            isEnabled: isEnabled,
            approval: approval,
            toolOrigin: ToolOrigin(
                type: .agentAsTool,
                agentName: self.name,
                agentToolName: toolName
            )
        ) { toolContext, arguments in
            let resolvedInput = try await AgentToolInputHelpers.resolveAgentToolInput(
                params: arguments,
                schemaInfo: shouldCaptureStructuredInput ? schemaInfo : nil,
                inputBuilder: inputBuilder
            )
            var resolvedRunConfig = runConfig ?? toolContext.runConfig ?? RunConfig()
            if let onStream {
                AgentToolStreaming.configure(
                    runConfig: &resolvedRunConfig,
                    onStream: onStream,
                    toolCall: toolContext.call
                )
            }
            let resolvedMaxTurns = maxTurns ?? RunConfigDefaults.defaultMaxTurns
            let scopeID = toolContext.runContext.runID
            var result: RunResult

            if let pendingResult = await AgentToolState.peek(call: toolContext.call, scopeID: scopeID),
               pendingResult.isInterrupted {
                switch AgentToolApprovals.nestedStatus(
                    interruptions: pendingResult.interruptions,
                    parentContext: toolContext.runContext
                ) {
                case .pending:
                    return .text("")
                case .readyToResume:
                    guard var nestedState = pendingResult.state(as: Context.self) else {
                        return .text(AgentToolOutput.defaultOutput(from: pendingResult))
                    }
                    AgentToolApprovals.applyNestedApprovals(
                        from: toolContext.runContext,
                        to: &nestedState,
                        interruptions: pendingResult.interruptions
                    )
                    _ = await AgentToolState.consume(call: toolContext.call, scopeID: scopeID)
                    result = try await Runner.run(state: nestedState)
                }
            } else {
                switch resolvedInput {
                case .text(let input):
                    result = try await Runner.run(
                        agent: self,
                        input: input,
                        context: toolContext.runContext.context,
                        maxTurns: resolvedMaxTurns,
                        hooks: hooks,
                        modelProvider: modelProvider,
                        runConfig: resolvedRunConfig,
                        session: session
                    )
                case .items(let input):
                    result = try await Runner.run(
                        agent: self,
                        input: input,
                        context: toolContext.runContext.context,
                        maxTurns: resolvedMaxTurns,
                        hooks: hooks,
                        modelProvider: modelProvider,
                        runConfig: resolvedRunConfig,
                        session: session
                    )
                }
            }

            result.agentToolInvocation = AgentToolInvocation(
                toolName: toolName,
                toolCallID: toolContext.call.callID,
                toolArguments: toolContext.call.arguments
            )
            if result.isInterrupted {
                await AgentToolState.record(result, for: toolContext.call, scopeID: scopeID)
            }
            if let customOutputExtractor {
                return .text(try await customOutputExtractor(result))
            }
            return .text(AgentToolOutput.defaultOutput(from: result))
        }
    }

    static func defaultToolName(for agentName: String) -> String {
        TransformUtils.transformStringFunctionStyle(agentName)
    }
}
