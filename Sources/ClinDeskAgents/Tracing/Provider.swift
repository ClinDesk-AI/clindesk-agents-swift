import Foundation

public enum SpanParent: Sendable {
    case trace(Trace)
    case span(Span)
}

public protocol TraceProvider: Sendable {
    func registerProcessor(_ processor: any TracingProcessor) async
    func setProcessors(_ processors: [any TracingProcessor]) async
    func setDisabled(_ disabled: Bool) async
    func createTrace(
        name: String,
        traceID: String?,
        groupID: String?,
        metadata: [String: JSONValue]?,
        disabled: Bool
    ) async -> Trace
    func createSpan(
        spanData: any SpanData,
        spanID: String?,
        parent: SpanParent?,
        disabled: Bool
    ) async -> Span
    func onTraceStart(_ trace: Trace) async
    func onTraceEnd(_ trace: Trace) async
    func onSpanStart(_ span: Span) async
    func onSpanEnd(_ span: Span) async
    func forceFlush() async
    func shutdown() async
}

public actor DefaultTraceProvider: TraceProvider {
    private var processors: [any TracingProcessor] = []
    private var disabled = false

    public init() {}

    public func registerProcessor(_ processor: any TracingProcessor) {
        processors.append(processor)
    }

    public func setProcessors(_ processors: [any TracingProcessor]) {
        self.processors = processors
    }

    public func setDisabled(_ disabled: Bool) {
        self.disabled = disabled
    }

    public func createTrace(
        name: String,
        traceID: String?,
        groupID: String?,
        metadata: [String: JSONValue]?,
        disabled traceDisabled: Bool
    ) -> Trace {
        guard !disabled, !traceDisabled else {
            return .noOp()
        }
        return Trace(
            id: traceID ?? TracingIDs.genTraceID(),
            workflowName: name,
            groupID: groupID,
            metadata: metadata ?? [:]
        )
    }

    public func createSpan(
        spanData: any SpanData,
        spanID: String?,
        parent: SpanParent?,
        disabled spanDisabled: Bool
    ) -> Span {
        guard !disabled, !spanDisabled, spanID != "no-op" else {
            return .noOp(spanData: spanData)
        }

        let resolvedParent: SpanParent
        if let parent {
            resolvedParent = parent
        } else if let currentTrace = TracingScope.getCurrentTrace() {
            if let currentSpan = TracingScope.getCurrentSpan() {
                resolvedParent = .span(currentSpan)
            } else {
                resolvedParent = .trace(currentTrace)
            }
        } else {
            return .noOp(spanData: spanData)
        }

        switch resolvedParent {
        case .trace(let trace):
            guard !trace.isNoOp else {
                return .noOp(spanData: spanData)
            }
            return Span(
                spanData: spanData,
                traceID: trace.traceID,
                spanID: spanID ?? TracingIDs.genSpanID(),
                traceMetadata: trace.metadata
            )
        case .span(let span):
            guard !span.isNoOp else {
                return .noOp(spanData: spanData)
            }
            return Span(
                spanData: spanData,
                traceID: span.traceID,
                spanID: spanID ?? TracingIDs.genSpanID(),
                parentID: span.spanID,
                traceMetadata: span.traceMetadata
            )
        }
    }

    public func onTraceStart(_ trace: Trace) async {
        guard !disabled, !trace.isNoOp else {
            return
        }
        for processor in processors {
            await processor.onTraceStart(trace)
        }
    }

    public func onTraceEnd(_ trace: Trace) async {
        guard !disabled, !trace.isNoOp else {
            return
        }
        for processor in processors {
            await processor.onTraceEnd(trace)
        }
    }

    public func onSpanStart(_ span: Span) async {
        guard !disabled, !span.isNoOp else {
            return
        }
        for processor in processors {
            await processor.onSpanStart(span)
        }
    }

    public func onSpanEnd(_ span: Span) async {
        guard !disabled, !span.isNoOp else {
            return
        }
        for processor in processors {
            await processor.onSpanEnd(span)
        }
    }

    public func forceFlush() async {
        guard !disabled else {
            return
        }
        for processor in processors {
            await processor.forceFlush()
        }
    }

    public func shutdown() async {
        guard !disabled else {
            return
        }
        for processor in processors {
            await processor.shutdown()
        }
    }
}
