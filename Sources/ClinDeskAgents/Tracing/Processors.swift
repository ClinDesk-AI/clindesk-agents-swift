import Foundation

public actor InMemoryTracingProcessor: TracingProcessor {
    private var traceStarts: [Trace] = []
    private var traceEnds: [Trace] = []
    private var spanStarts: [Span] = []
    private var spanEnds: [Span] = []

    public init() {}

    public func onTraceStart(_ trace: Trace) async {
        traceStarts.append(trace)
    }

    public func onTraceEnd(_ trace: Trace) async {
        traceEnds.append(trace)
    }

    public func onSpanStart(_ span: Span) async {
        spanStarts.append(span)
    }

    public func onSpanEnd(_ span: Span) async {
        spanEnds.append(span)
    }

    public func allTraces() -> [Trace] {
        traceEnds
    }

    public func startedTraces() -> [Trace] {
        traceStarts
    }

    public func endedTraces() -> [Trace] {
        traceEnds
    }

    public func startedSpans() -> [Span] {
        spanStarts
    }

    public func endedSpans() -> [Span] {
        spanEnds
    }
}
