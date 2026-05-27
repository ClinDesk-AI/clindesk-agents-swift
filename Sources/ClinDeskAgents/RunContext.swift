import Foundation

public struct ToolApprovalRecord: Equatable, Sendable {
    public var approved: Set<String>
    public var rejected: Set<String>
    public var alwaysApproved: Bool
    public var alwaysRejected: Bool
    public var rejectionMessages: [String: String]
    public var stickyRejectionMessage: String?

    public init(
        approved: Set<String> = [],
        rejected: Set<String> = [],
        alwaysApproved: Bool = false,
        alwaysRejected: Bool = false,
        rejectionMessages: [String: String] = [:],
        stickyRejectionMessage: String? = nil
    ) {
        self.approved = approved
        self.rejected = rejected
        self.alwaysApproved = alwaysApproved
        self.alwaysRejected = alwaysRejected
        self.rejectionMessages = rejectionMessages
        self.stickyRejectionMessage = stickyRejectionMessage
    }
}

public struct RunContext<Context: Sendable>: Sendable {
    public var runID: String
    public var context: Context?
    public var usage: Usage
    public var metadata: [String: JSONValue]
    public var approvals: [String: ToolApprovalRecord]
    public var cancellation: @Sendable () -> Bool

    public init(
        runID: String = UUID().uuidString,
        context: Context? = nil,
        usage: Usage = Usage(),
        metadata: [String: JSONValue] = [:],
        approvals: [String: ToolApprovalRecord] = [:],
        cancellation: @escaping @Sendable () -> Bool = { false }
    ) {
        self.runID = runID
        self.context = context
        self.usage = usage
        self.metadata = metadata
        self.approvals = approvals
        self.cancellation = cancellation
    }

    public func throwingIfCancelled() throws {
        if cancellation() {
            throw AgentsError.cancelled
        }
    }

    public func approvalStatus(
        toolName: String,
        callID: String,
        toolNamespace: String? = nil,
        existingPending: ToolApprovalItem? = nil,
        toolLookupKey: FunctionToolLookupKey? = nil
    ) -> Bool? {
        for approvalKey in approvalCandidateKeys(
            toolName: toolName,
            toolNamespace: toolNamespace,
            existingPending: existingPending,
            toolLookupKey: toolLookupKey
        ) {
            if let status = approvalStatus(forKey: approvalKey, callID: callID) {
                return status
            }
        }
        return nil
    }

    private func approvalStatus(forKey approvalKey: String, callID: String) -> Bool? {
        guard let record = approvals[approvalKey] else {
            return nil
        }
        if record.alwaysApproved && record.alwaysRejected {
            return true
        }
        if record.alwaysApproved {
            return true
        }
        if record.alwaysRejected {
            return false
        }
        if record.approved.contains(callID) {
            return true
        }
        if record.rejected.contains(callID) {
            return false
        }
        return nil
    }

    public func rejectionMessage(
        toolName: String,
        callID: String,
        toolNamespace: String? = nil,
        existingPending: ToolApprovalItem? = nil,
        toolLookupKey: FunctionToolLookupKey? = nil
    ) -> String? {
        for approvalKey in approvalCandidateKeys(
            toolName: toolName,
            toolNamespace: toolNamespace,
            existingPending: existingPending,
            toolLookupKey: toolLookupKey
        ) {
            guard let record = approvals[approvalKey] else {
                continue
            }
            if let message = rejectionMessage(for: record, callID: callID) {
                return message
            }
        }
        return nil
    }

    private func rejectionMessage(for record: ToolApprovalRecord, callID: String) -> String? {
        if let message = record.rejectionMessages[callID] {
            return message
        }
        if record.alwaysRejected {
            return record.stickyRejectionMessage
        }
        return nil
    }

    public mutating func approveTool(_ item: ToolApprovalItem, alwaysApprove: Bool = false) {
        for approvalKey in decisionApprovalKeys(for: item, always: alwaysApprove) {
            var record = approvals[approvalKey] ?? ToolApprovalRecord()
            if alwaysApprove {
                record.alwaysApproved = true
                record.alwaysRejected = false
                record.approved.removeAll()
                record.rejected.removeAll()
                record.rejectionMessages.removeAll()
                record.stickyRejectionMessage = nil
            } else {
                record.approved.insert(item.callID)
                record.rejected.remove(item.callID)
                record.rejectionMessages.removeValue(forKey: item.callID)
            }
            approvals[approvalKey] = record
        }
    }

    public mutating func rejectTool(
        _ item: ToolApprovalItem,
        alwaysReject: Bool = false,
        rejectionMessage: String? = nil
    ) {
        for approvalKey in decisionApprovalKeys(for: item, always: alwaysReject) {
            var record = approvals[approvalKey] ?? ToolApprovalRecord()
            if alwaysReject {
                record.alwaysRejected = true
                record.alwaysApproved = false
                record.approved.removeAll()
                record.rejected.removeAll()
                record.rejectionMessages.removeAll()
                if let rejectionMessage {
                    record.rejectionMessages[item.callID] = rejectionMessage
                }
                record.stickyRejectionMessage = rejectionMessage
            } else {
                record.rejected.insert(item.callID)
                record.approved.remove(item.callID)
                if let rejectionMessage {
                    record.rejectionMessages[item.callID] = rejectionMessage
                } else {
                    record.rejectionMessages.removeValue(forKey: item.callID)
                }
            }
            approvals[approvalKey] = record
        }
    }

    private func decisionApprovalKeys(for item: ToolApprovalItem, always: Bool) -> [String] {
        let exactKey = resolvedApprovalKey(for: item)
        if always {
            return [exactKey]
        }
        let keys = resolvedApprovalKeys(for: item)
        return keys.isEmpty ? ["unknown_tool"] : keys
    }

    private func resolvedApprovalKey(for item: ToolApprovalItem) -> String {
        let keys = ToolIdentity.functionToolApprovalKeys(
            toolName: item.toolName,
            toolNamespace: item.toolNamespace,
            toolLookupKey: item.toolLookupKey,
            preferLegacySameNameNamespace: item.toolLookupKey == nil
        )
        return keys.last ?? ToolIdentity.qualifiedName(
            name: item.toolName,
            namespace: item.toolNamespace
        ) ?? item.toolName
    }

    private func resolvedApprovalKeys(for item: ToolApprovalItem) -> [String] {
        ToolIdentity.functionToolApprovalKeys(
            toolName: item.toolName,
            toolNamespace: item.toolNamespace,
            allowBareNameAlias: item.allowBareNameAlias,
            toolLookupKey: item.toolLookupKey,
            preferLegacySameNameNamespace: item.toolLookupKey == nil
        )
    }

    private func approvalCandidateKeys(
        toolName: String,
        toolNamespace: String?,
        existingPending: ToolApprovalItem?,
        toolLookupKey: FunctionToolLookupKey?
    ) -> [String] {
        var candidates: [String] = []
        func appendCandidate(_ candidate: String?) {
            guard let candidate, !candidates.contains(candidate) else {
                return
            }
            candidates.append(candidate)
        }

        let explicitNamespace = nonEmpty(toolNamespace)
        let pendingNamespace = existingPending.flatMap { nonEmpty($0.toolNamespace) }
        let pendingKey = existingPending.map(resolvedApprovalKey)
        let pendingToolName = existingPending.flatMap { nonEmpty($0.toolName) }
        let pendingKeys = existingPending.map(resolvedApprovalKeys) ?? []

        if existingPending != nil {
            appendCandidate(pendingKey)
        }

        let explicitKeys: [String]
        if explicitNamespace != nil || toolLookupKey != nil {
            explicitKeys = ToolIdentity.functionToolApprovalKeys(
                toolName: toolName,
                toolNamespace: explicitNamespace,
                toolLookupKey: toolLookupKey,
                includeLegacyDeferredKey: true
            )
        } else {
            explicitKeys = []
        }
        for key in explicitKeys {
            appendCandidate(key)
        }

        if explicitKeys.isEmpty, pendingNamespace != nil {
            appendCandidate(pendingKey)
        }

        if explicitNamespace == nil, toolLookupKey == nil, existingPending == nil {
            appendCandidate(toolName)
        }

        if existingPending != nil {
            for key in pendingKeys {
                appendCandidate(key)
            }
            if pendingNamespace == nil {
                appendCandidate(pendingToolName)
            }
        }

        return candidates
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
