import Foundation

public actor TraceProviderRegistry {
    public static let shared = TraceProviderRegistry()

    private var provider: any TraceProvider = DefaultTraceProvider()

    public func getTraceProvider() -> any TraceProvider {
        provider
    }

    public func setTraceProvider(_ provider: any TraceProvider) {
        self.provider = provider
    }
}

public func getTraceProvider() async -> any TraceProvider {
    await TraceProviderRegistry.shared.getTraceProvider()
}

public func setTraceProvider(_ provider: any TraceProvider) async {
    await TraceProviderRegistry.shared.setTraceProvider(provider)
}

public func addTraceProcessor(_ processor: any TracingProcessor) async {
    await (await getTraceProvider()).registerProcessor(processor)
}

public func setTraceProcessors(_ processors: [any TracingProcessor]) async {
    await (await getTraceProvider()).setProcessors(processors)
}

public func setTracingDisabled(_ disabled: Bool) async {
    await (await getTraceProvider()).setDisabled(disabled)
}

public func flushTraces() async {
    await (await getTraceProvider()).forceFlush()
}
