import Foundation

extension RunnerLoop {
    func planFunctionToolCalls(
        _ calls: [FunctionCall],
        tools: [FunctionTool<Context>],
        toolsByLookupKey: [FunctionToolLookupKey: FunctionTool<Context>],
        context: RunContext<Context>,
        trace: inout Trace
    ) async throws -> FunctionToolExecutionPlan<Context> {
        var plan = FunctionToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            guard let tool = Self.functionTool(for: call, in: toolsByLookupKey) else {
                throw AgentsError.toolNotFound(call.name)
            }
            let toolOrigin = call.toolOrigin ?? tool.resolvedToolOrigin
            let originCall = call.withToolOrigin(toolOrigin)
            trace.items.append(.toolCall(originCall))
            let toolNamespace = originCall.namespace ?? tool.descriptor.namespace
            let toolLookupKey = ToolIdentity.functionToolLookupKey(for: tool)
            let approvalItem = ToolApprovalItem(
                toolName: tool.descriptor.name,
                callID: originCall.callID,
                arguments: originCall.arguments,
                tool: .function(tool.descriptor),
                toolNamespace: toolNamespace,
                allowBareNameAlias: ToolIdentity.shouldAllowBareNameApprovalAlias(
                    for: tool,
                    allTools: tools
                ),
                toolLookupKey: toolLookupKey,
                toolOrigin: toolOrigin
            )

            if let approval = tool.approval {
                switch context.approvalStatus(
                    toolName: tool.descriptor.name,
                    callID: originCall.callID,
                    toolNamespace: toolNamespace,
                    toolLookupKey: toolLookupKey
                ) {
                case .some(true):
                    break
                case .some(false):
                    let message: String
                    if let rejectionMessage = context.rejectionMessage(
                        toolName: tool.descriptor.name,
                        callID: originCall.callID,
                        toolNamespace: toolNamespace,
                        toolLookupKey: toolLookupKey
                    ) {
                        message = rejectionMessage
                    } else {
                        message = await resolveApprovalRejectedMessage(
                            toolName: tool.descriptor.name,
                            callID: originCall.callID,
                            context: context
                        )
                    }
                    plan.immediateResults[offset] = ToolRunResult(
                        call: originCall,
                        output: .text(message),
                        toolOrigin: toolOrigin
                    )
                    continue
                case .none:
                    let needsApproval = try await approval(ToolApprovalRequest(
                        context: context,
                        tool: tool.descriptor,
                        call: originCall
                    ))
                    if needsApproval {
                        plan.interruptions.append(approvalItem)
                        continue
                    }
                }
            }
            plan.scheduled.append(FunctionToolRun(offset: offset, tool: tool, call: originCall))
        }
        return plan
    }

    func planCustomToolCalls(
        _ calls: [CustomToolCall],
        tools: [CustomTool<Context>],
        context: inout RunContext<Context>,
        trace: inout Trace
    ) async throws -> CustomToolExecutionPlan<Context> {
        var plan = CustomToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            guard let tool = tools.first(where: { $0.descriptor.name == call.name }) else {
                throw AgentsError.toolNotFound(call.name)
            }
            trace.items.append(.customToolCall(call))
            let approvalItem = ToolApprovalItem(
                toolName: tool.descriptor.name,
                callID: call.callID,
                arguments: .string(call.input),
                tool: .custom(tool.descriptor)
            )

            switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
            case .some(true):
                plan.scheduled.append(CustomToolRun(offset: offset, tool: tool, call: call))
            case .some(false):
                let message: String
                if let rejectionMessage = context.rejectionMessage(
                    toolName: tool.descriptor.name,
                    callID: call.callID
                ) {
                    message = rejectionMessage
                } else {
                    message = await resolveApprovalRejectedMessage(
                        toolName: tool.descriptor.name,
                        callID: call.callID,
                        context: context,
                        toolType: .custom
                    )
                }
                plan.immediateResults[offset] = CustomToolRunResult(call: call, output: message)
            case .none:
                let request = CustomToolApprovalRequest(
                    context: context,
                    tool: tool.descriptor,
                    call: call
                )
                if try await tool.needsApproval(request) {
                    if let decision = try await tool.onApproval?(ToolOnApprovalRequest(
                        context: context,
                        item: approvalItem
                    )) {
                        if decision.approve {
                            context.approveTool(approvalItem)
                            plan.scheduled.append(CustomToolRun(offset: offset, tool: tool, call: call))
                        } else {
                            context.rejectTool(approvalItem, rejectionMessage: decision.reason)
                            let message = await resolveApprovalRejectedMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID,
                                context: context,
                                toolType: .custom
                            )
                            plan.immediateResults[offset] = CustomToolRunResult(call: call, output: message)
                        }
                    } else {
                        switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
                        case .some(true):
                            plan.scheduled.append(CustomToolRun(offset: offset, tool: tool, call: call))
                        case .some(false):
                            let message: String
                            if let rejectionMessage = context.rejectionMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID
                            ) {
                                message = rejectionMessage
                            } else {
                                message = await resolveApprovalRejectedMessage(
                                    toolName: tool.descriptor.name,
                                    callID: call.callID,
                                    context: context,
                                    toolType: .custom
                                )
                            }
                            plan.immediateResults[offset] = CustomToolRunResult(call: call, output: message)
                        case .none:
                            plan.interruptions.append(approvalItem)
                        }
                    }
                } else {
                    plan.scheduled.append(CustomToolRun(offset: offset, tool: tool, call: call))
                }
            }
        }
        return plan
    }

    func planComputerCalls(
        _ calls: [ComputerCall],
        tools: [ComputerTool<Context>],
        trace: inout Trace
    ) throws -> ComputerToolExecutionPlan<Context> {
        guard !calls.isEmpty else {
            return ComputerToolExecutionPlan<Context>()
        }
        guard let tool = tools.first else {
            throw AgentsError.toolNotFound("computer")
        }
        var plan = ComputerToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            trace.items.append(.computerCall(call))
            plan.scheduled.append(ComputerToolRun(offset: offset, tool: tool, call: call))
        }
        return plan
    }

    func planLocalShellCalls(
        _ calls: [LocalShellCall],
        tools: [LocalShellTool<Context>],
        trace: inout Trace
    ) throws -> LocalShellToolExecutionPlan<Context> {
        guard !calls.isEmpty else {
            return LocalShellToolExecutionPlan<Context>()
        }
        guard let tool = tools.first else {
            throw AgentsError.toolNotFound("local_shell")
        }
        var plan = LocalShellToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            trace.items.append(.localShellCall(call))
            plan.scheduled.append(LocalShellToolRun(offset: offset, tool: tool, call: call))
        }
        return plan
    }

    func planShellCalls(
        _ calls: [ShellCall],
        tools: [ShellTool<Context>],
        context: inout RunContext<Context>,
        trace: inout Trace
    ) async throws -> ShellToolExecutionPlan<Context> {
        guard !calls.isEmpty else {
            return ShellToolExecutionPlan<Context>()
        }
        guard let tool = tools.first else {
            throw AgentsError.toolNotFound("shell")
        }
        var plan = ShellToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            trace.items.append(.shellCall(call))
            let approvalItem = ToolApprovalItem(
                toolName: tool.descriptor.name,
                callID: call.callID,
                arguments: (try? JSONValue.encoded(call.action)) ?? .emptyObject,
                tool: .shell(tool.descriptor)
            )

            switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
            case .some(true):
                plan.scheduled.append(ShellToolRun(offset: offset, tool: tool, call: call))
            case .some(false):
                let message: String
                if let rejectionMessage = context.rejectionMessage(
                    toolName: tool.descriptor.name,
                    callID: call.callID
                ) {
                    message = rejectionMessage
                } else {
                    message = await resolveApprovalRejectedMessage(
                        toolName: tool.descriptor.name,
                        callID: call.callID,
                        context: context,
                        toolType: .shell
                    )
                }
                plan.immediateResults[offset] = rejectedShellResult(call: call, message: message)
            case .none:
                if try await shellNeedsApproval(tool.needsApproval, context: context, call: call) {
                    if let decision = try await tool.onApproval?(ToolOnApprovalRequest(
                        context: context,
                        item: approvalItem
                    )) {
                        if decision.approve {
                            context.approveTool(approvalItem)
                            plan.scheduled.append(ShellToolRun(offset: offset, tool: tool, call: call))
                        } else {
                            context.rejectTool(approvalItem, rejectionMessage: decision.reason)
                            let message = await resolveApprovalRejectedMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID,
                                context: context,
                                toolType: .shell
                            )
                            plan.immediateResults[offset] = rejectedShellResult(call: call, message: message)
                        }
                    } else {
                        switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
                        case .some(true):
                            plan.scheduled.append(ShellToolRun(offset: offset, tool: tool, call: call))
                        case .some(false):
                            let message: String
                            if let rejectionMessage = context.rejectionMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID
                            ) {
                                message = rejectionMessage
                            } else {
                                message = await resolveApprovalRejectedMessage(
                                    toolName: tool.descriptor.name,
                                    callID: call.callID,
                                    context: context,
                                    toolType: .shell
                                )
                            }
                            plan.immediateResults[offset] = rejectedShellResult(call: call, message: message)
                        case .none:
                            plan.interruptions.append(approvalItem)
                        }
                    }
                } else {
                    plan.scheduled.append(ShellToolRun(offset: offset, tool: tool, call: call))
                }
            }
        }
        return plan
    }

    func planApplyPatchCalls(
        _ calls: [ApplyPatchCall],
        tools: [ApplyPatchTool<Context>],
        context: inout RunContext<Context>,
        trace: inout Trace
    ) async throws -> ApplyPatchToolExecutionPlan<Context> {
        guard !calls.isEmpty else {
            return ApplyPatchToolExecutionPlan<Context>()
        }
        guard let tool = tools.first else {
            throw AgentsError.toolNotFound("apply_patch")
        }
        var plan = ApplyPatchToolExecutionPlan<Context>()
        for (offset, call) in calls.enumerated() {
            trace.items.append(.applyPatchCall(call))
            let approvalItem = ToolApprovalItem(
                toolName: tool.descriptor.name,
                callID: call.callID,
                arguments: .array(call.operations.map { (try? JSONValue.encoded($0)) ?? .emptyObject }),
                tool: .applyPatch(tool.descriptor)
            )

            switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
            case .some(true):
                plan.scheduled.append(ApplyPatchToolRun(offset: offset, tool: tool, call: call))
            case .some(false):
                let message: String
                if let rejectionMessage = context.rejectionMessage(
                    toolName: tool.descriptor.name,
                    callID: call.callID
                ) {
                    message = rejectionMessage
                } else {
                    message = await resolveApprovalRejectedMessage(
                        toolName: tool.descriptor.name,
                        callID: call.callID,
                        context: context,
                        toolType: .applyPatch
                    )
                }
                plan.immediateResults[offset] = ApplyPatchRunResult(
                    call: call,
                    status: .failed,
                    output: message
                )
            case .none:
                if try await applyPatchNeedsApproval(tool.needsApproval, context: context, call: call) {
                    if let decision = try await tool.onApproval?(ToolOnApprovalRequest(
                        context: context,
                        item: approvalItem
                    )) {
                        if decision.approve {
                            context.approveTool(approvalItem)
                            plan.scheduled.append(ApplyPatchToolRun(offset: offset, tool: tool, call: call))
                        } else {
                            context.rejectTool(approvalItem, rejectionMessage: decision.reason)
                            let message = await resolveApprovalRejectedMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID,
                                context: context,
                                toolType: .applyPatch
                            )
                            plan.immediateResults[offset] = ApplyPatchRunResult(
                                call: call,
                                status: .failed,
                                output: message
                            )
                        }
                    } else {
                        switch context.approvalStatus(toolName: tool.descriptor.name, callID: call.callID) {
                        case .some(true):
                            plan.scheduled.append(ApplyPatchToolRun(offset: offset, tool: tool, call: call))
                        case .some(false):
                            let message: String
                            if let rejectionMessage = context.rejectionMessage(
                                toolName: tool.descriptor.name,
                                callID: call.callID
                            ) {
                                message = rejectionMessage
                            } else {
                                message = await resolveApprovalRejectedMessage(
                                    toolName: tool.descriptor.name,
                                    callID: call.callID,
                                    context: context,
                                    toolType: .applyPatch
                                )
                            }
                            plan.immediateResults[offset] = ApplyPatchRunResult(
                                call: call,
                                status: .failed,
                                output: message
                            )
                        case .none:
                            plan.interruptions.append(approvalItem)
                        }
                    }
                } else {
                    plan.scheduled.append(ApplyPatchToolRun(offset: offset, tool: tool, call: call))
                }
            }
        }
        return plan
    }

    private func shellNeedsApproval(
        _ setting: ShellToolApproval<Context>,
        context: RunContext<Context>,
        call: ShellCall
    ) async throws -> Bool {
        switch setting {
        case .never:
            return false
        case .always:
            return true
        case .dynamic(let predicate):
            return try await predicate(context, call.action, call.callID)
        }
    }

    private func applyPatchNeedsApproval(
        _ setting: ApplyPatchToolApproval<Context>,
        context: RunContext<Context>,
        call: ApplyPatchCall
    ) async throws -> Bool {
        switch setting {
        case .never:
            return false
        case .always:
            return true
        case .dynamic(let predicate):
            for operation in call.operations {
                if try await predicate(context, operation, call.callID) {
                    return true
                }
            }
            return false
        }
    }

    private func rejectedShellResult(call: ShellCall, message: String) -> ShellRunResult {
        ShellRunResult(
            call: call,
            output: .array([
                .object([
                    "stdout": .string(""),
                    "stderr": .string(message),
                    "outcome": .object([
                        "type": .string(ShellCallOutcomeType.exit.rawValue),
                        "exit_code": .number(1)
                    ])
                ])
            ]),
            status: "failed"
        )
    }
}
