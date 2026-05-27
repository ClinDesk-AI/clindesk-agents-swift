enum NestedAgentToolApprovalStatus {
    case pending
    case readyToResume
}

enum AgentToolApprovals {
    static func nestedStatus<Context: Sendable>(
        interruptions: [ToolApprovalItem],
        parentContext: RunContext<Context>
    ) -> NestedAgentToolApprovalStatus {
        for interruption in interruptions {
            let status = parentContext.approvalStatus(
                toolName: interruption.toolName,
                callID: interruption.callID,
                toolNamespace: interruption.toolNamespace,
                existingPending: interruption,
                toolLookupKey: interruption.toolLookupKey
            )
            if status == nil {
                return .pending
            }
        }
        return .readyToResume
    }

    static func applyNestedApprovals<Context: Sendable>(
        from parentContext: RunContext<Context>,
        to nestedState: inout RunState<Context>,
        interruptions: [ToolApprovalItem]
    ) {
        for interruption in interruptions {
            let status = parentContext.approvalStatus(
                toolName: interruption.toolName,
                callID: interruption.callID,
                toolNamespace: interruption.toolNamespace,
                existingPending: interruption,
                toolLookupKey: interruption.toolLookupKey
            )
            switch status {
            case .some(true):
                nestedState.approve(interruption)
            case .some(false):
                let rejectionMessage = parentContext.rejectionMessage(
                    toolName: interruption.toolName,
                    callID: interruption.callID,
                    toolNamespace: interruption.toolNamespace,
                    existingPending: interruption,
                    toolLookupKey: interruption.toolLookupKey
                )
                nestedState.reject(interruption, rejectionMessage: rejectionMessage)
            case .none:
                continue
            }
        }
    }
}
