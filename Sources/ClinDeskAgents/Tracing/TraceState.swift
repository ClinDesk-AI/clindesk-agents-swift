import Foundation

public struct TraceState: Equatable, Sendable {
    public var traceID: String?
    public var workflowName: String?
    public var groupID: String?
    public var metadata: [String: JSONValue]?
    public var objectType: String?
    public var extra: [String: JSONValue]

    public init(
        traceID: String? = nil,
        workflowName: String? = nil,
        groupID: String? = nil,
        metadata: [String: JSONValue]? = nil,
        objectType: String? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.traceID = traceID
        self.workflowName = workflowName
        self.groupID = groupID
        self.metadata = metadata
        self.objectType = objectType
        self.extra = extra
    }

    public static func fromTrace(_ trace: Trace?) -> TraceState? {
        guard let payload = trace?.toJSON() else {
            return nil
        }
        return fromJSON(payload)
    }

    public static func fromJSON(_ payload: [String: JSONValue]?) -> TraceState? {
        guard var data = payload, !data.isEmpty else {
            return nil
        }

        let objectType = data.removeString(forKey: "object")
        let traceID = data.removeString(forKey: "id") ?? data.removeString(forKey: "trace_id")
        let workflowName = data.removeString(forKey: "workflow_name")
        let groupID = data.removeString(forKey: "group_id")
        let metadata = data.removeObject(forKey: "metadata")

        return TraceState(
            traceID: traceID,
            workflowName: workflowName,
            groupID: groupID,
            metadata: metadata,
            objectType: objectType,
            extra: data
        )
    }

    public func toJSON() -> [String: JSONValue]? {
        guard traceID != nil
            || workflowName != nil
            || groupID != nil
            || metadata != nil
            || objectType != nil
            || !extra.isEmpty
        else {
            return nil
        }

        var payload: [String: JSONValue] = [:]
        if let objectType {
            payload["object"] = .string(objectType)
        }
        if let traceID {
            payload["id"] = .string(traceID)
        }
        if let workflowName {
            payload["workflow_name"] = .string(workflowName)
        }
        if let groupID {
            payload["group_id"] = .string(groupID)
        }
        if let metadata {
            payload["metadata"] = .object(metadata)
        }
        for (key, value) in extra where payload[key] == nil {
            payload[key] = value
        }
        return payload
    }
}

public func reattachTrace(
    from traceState: TraceState
) -> Trace? {
    guard let traceID = traceState.traceID else {
        return nil
    }
    return Trace(
        id: traceID,
        workflowName: traceState.workflowName ?? "Agent workflow",
        groupID: traceState.groupID,
        metadata: traceState.metadata ?? [:]
    )
}

private extension Dictionary where Key == String, Value == JSONValue {
    mutating func removeString(forKey key: String) -> String? {
        guard case .string(let value) = removeValue(forKey: key) else {
            return nil
        }
        return value
    }

    mutating func removeObject(forKey key: String) -> [String: JSONValue]? {
        guard case .object(let value) = removeValue(forKey: key) else {
            return nil
        }
        return value
    }
}
