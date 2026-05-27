import Foundation

public struct Trace: Equatable, Sendable {
    public var id: String
    public var workflowName: String
    public var groupID: String?
    public var metadata: [String: JSONValue]
    public var includeSensitiveData: Bool
    public var isNoOp: Bool
    public var startedAt: Date
    public var endedAt: Date?
    public var items: [TraceItem]

    public init(
        id: String = TracingIDs.genTraceID(),
        workflowName: String = "Agent workflow",
        groupID: String? = nil,
        metadata: [String: JSONValue] = [:],
        includeSensitiveData: Bool = false,
        isNoOp: Bool = false,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        items: [TraceItem] = []
    ) {
        self.id = id
        self.workflowName = workflowName
        self.groupID = groupID
        self.metadata = metadata
        self.includeSensitiveData = includeSensitiveData
        self.isNoOp = isNoOp
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.items = items
    }

    public var traceID: String {
        id
    }

    public var name: String {
        workflowName
    }

    public static func noOp() -> Trace {
        Trace(id: "no-op", workflowName: "no-op", isNoOp: true)
    }

    public func export() -> [String: JSONValue]? {
        guard !isNoOp else {
            return nil
        }
        return [
            "object": "trace",
            "id": .string(id),
            "workflow_name": .string(workflowName),
            "group_id": groupID.map(JSONValue.string) ?? .null,
            "metadata": .object(metadata)
        ]
    }

    public func toJSON() -> [String: JSONValue]? {
        export()
    }

    public mutating func start(markAsCurrent: Bool = false) async {
        startedAt = Date()
        guard !isNoOp else {
            return
        }
        await (await getTraceProvider()).onTraceStart(self)
    }

    public mutating func finish(resetCurrent: Bool = false) async {
        endedAt = Date()
        guard !isNoOp else {
            return
        }
        await (await getTraceProvider()).onTraceEnd(self)
    }
}
