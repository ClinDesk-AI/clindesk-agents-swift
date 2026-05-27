import Foundation

public struct SpanError: Equatable, Sendable {
    public var message: String
    public var data: [String: JSONValue]?

    public init(message: String, data: [String: JSONValue]? = nil) {
        self.message = message
        self.data = data
    }

    public func export() -> [String: JSONValue] {
        [
            "message": .string(message),
            "data": data.map(JSONValue.object) ?? .null
        ]
    }
}

public struct Span: Sendable {
    public var traceID: String
    public var spanID: String
    public var parentID: String?
    public var spanData: any SpanData
    public var startedAt: Date?
    public var endedAt: Date?
    public var error: SpanError?
    public var traceMetadata: [String: JSONValue]?
    public var isNoOp: Bool

    public init(
        spanData: any SpanData,
        traceID: String,
        spanID: String = TracingIDs.genSpanID(),
        parentID: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        error: SpanError? = nil,
        traceMetadata: [String: JSONValue]? = nil,
        isNoOp: Bool = false
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentID = parentID
        self.spanData = spanData
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.error = error
        self.traceMetadata = traceMetadata
        self.isNoOp = isNoOp
    }

    public static func noOp(spanData: any SpanData) -> Span {
        Span(spanData: spanData, traceID: "no-op", spanID: "no-op", isNoOp: true)
    }

    public mutating func start(at date: Date = Date(), markAsCurrent: Bool = false) async {
        startedAt = date
        guard !isNoOp else {
            return
        }
        await (await getTraceProvider()).onSpanStart(self)
    }

    public mutating func finish(at date: Date = Date(), resetCurrent: Bool = false) async {
        endedAt = date
        guard !isNoOp else {
            return
        }
        await (await getTraceProvider()).onSpanEnd(self)
    }

    public mutating func setError(_ error: SpanError) {
        self.error = error
    }

    public func export() -> [String: JSONValue]? {
        guard !isNoOp else {
            return nil
        }
        var payload: [String: JSONValue] = [
            "object": "trace.span",
            "id": .string(spanID),
            "trace_id": .string(traceID),
            "parent_id": parentID.map(JSONValue.string) ?? .null,
            "started_at": startedAt.map { .string(TracingIDs.timeISO($0)) } ?? .null,
            "ended_at": endedAt.map { .string(TracingIDs.timeISO($0)) } ?? .null,
            "span_data": .object(spanData.export()),
            "error": error.map { .object($0.export()) } ?? .null
        ]

        var metadata: [String: JSONValue] = [:]
        if let harnessID = traceMetadata?["agent_harness_id"] {
            metadata["agent_harness_id"] = harnessID
        }
        if let spanMetadata = spanData.metadata {
            for (key, value) in spanMetadata where metadata[key] == nil {
                metadata[key] = value
            }
        }
        if !metadata.isEmpty {
            payload["metadata"] = .object(metadata)
        }
        return payload
    }
}
