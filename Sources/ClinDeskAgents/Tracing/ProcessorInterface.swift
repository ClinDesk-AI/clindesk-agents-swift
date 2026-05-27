import Foundation

public protocol TracingProcessor: Sendable {
    func onTraceStart(_ trace: Trace) async
    func onTraceEnd(_ trace: Trace) async
    func onSpanStart(_ span: Span) async
    func onSpanEnd(_ span: Span) async
    func shutdown() async
    func forceFlush() async
}

public extension TracingProcessor {
    func onTraceStart(_ trace: Trace) async {}
    func onTraceEnd(_ trace: Trace) async {}
    func onSpanStart(_ span: Span) async {}
    func onSpanEnd(_ span: Span) async {}
    func shutdown() async {}
    func forceFlush() async {}
}
