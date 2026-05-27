import Foundation

public enum TracingScope {
    @TaskLocal public static var currentTrace: Trace?
    @TaskLocal public static var currentSpan: Span?

    public static func getCurrentTrace() -> Trace? {
        currentTrace
    }

    public static func getCurrentSpan() -> Span? {
        currentSpan
    }
}

public func withTrace<Output: Sendable>(
    _ trace: Trace,
    operation: @Sendable () async throws -> Output
) async rethrows -> Output {
    var activeTrace = trace
    await activeTrace.start(markAsCurrent: true)
    do {
        let output = try await TracingScope.$currentTrace.withValue(activeTrace) {
            try await operation()
        }
        await activeTrace.finish(resetCurrent: true)
        return output
    } catch {
        await activeTrace.finish(resetCurrent: true)
        throw error
    }
}

public func withSpan<Output: Sendable>(
    _ span: Span,
    operation: @Sendable () async throws -> Output
) async rethrows -> Output {
    var activeSpan = span
    await activeSpan.start(markAsCurrent: true)
    do {
        let output = try await TracingScope.$currentSpan.withValue(activeSpan) {
            try await operation()
        }
        await activeSpan.finish(resetCurrent: true)
        return output
    } catch {
        await activeSpan.finish(resetCurrent: true)
        throw error
    }
}
