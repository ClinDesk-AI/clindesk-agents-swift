import Testing
import ClinDeskAgents

@Suite
struct TraceProviderTests {
    @Test
    func defaultProviderCreatesTraceAndDispatchesLifecycleCallbacks() async {
        let provider = DefaultTraceProvider()
        let processor = InMemoryTracingProcessor()
        await provider.registerProcessor(processor)

        var trace = await provider.createTrace(
            name: "Checkout",
            traceID: "trace_checkout",
            groupID: "group_order",
            metadata: ["agent_harness_id": "harness"],
            disabled: false
        )
        await provider.onTraceStart(trace)
        trace.items.append(.finalOutput("done"))
        await provider.onTraceEnd(trace)

        #expect(await processor.startedTraces().map(\.traceID) == ["trace_checkout"])
        #expect(await processor.endedTraces().map(\.items) == [[.finalOutput("done")]])
    }

    @Test
    func defaultProviderCreatesNoOpTraceAndSpanWhenDisabled() async {
        let provider = DefaultTraceProvider()
        await provider.setDisabled(true)

        let trace = await provider.createTrace(
            name: "Disabled",
            traceID: nil,
            groupID: nil,
            metadata: nil,
            disabled: false
        )
        let span = await provider.createSpan(
            spanData: FunctionSpanData(name: "lookup"),
            spanID: nil,
            parent: .trace(trace),
            disabled: false
        )

        #expect(trace.isNoOp)
        #expect(trace.export() == nil)
        #expect(span.isNoOp)
        #expect(span.export() == nil)
    }

    @Test
    func defaultProviderResolvesExplicitTraceAndSpanParents() async {
        let provider = DefaultTraceProvider()
        let trace = await provider.createTrace(
            name: "Checkout",
            traceID: "trace_checkout",
            groupID: nil,
            metadata: ["agent_harness_id": "trace-harness"],
            disabled: false
        )
        let root = await provider.createSpan(
            spanData: AgentSpanData(name: "Assistant"),
            spanID: "span_agent",
            parent: .trace(trace),
            disabled: false
        )
        let child = await provider.createSpan(
            spanData: FunctionSpanData(name: "lookup"),
            spanID: "span_tool",
            parent: .span(root),
            disabled: false
        )

        #expect(root.traceID == "trace_checkout")
        #expect(root.parentID == nil)
        #expect(root.traceMetadata == ["agent_harness_id": "trace-harness"])
        #expect(child.traceID == "trace_checkout")
        #expect(child.parentID == "span_agent")
    }

    @Test
    func taskLocalScopeResolvesCurrentTraceAndSpanParents() async {
        let trace = Trace(id: "trace_scope", workflowName: "Scoped")

        await withTrace(trace) {
            #expect(getCurrentTrace()?.traceID == "trace_scope")

            let root = await functionSpan(name: "lookup", spanID: "span_lookup")
            #expect(root.traceID == "trace_scope")
            #expect(root.parentID == nil)

            await withSpan(root) {
                #expect(getCurrentSpan()?.spanID == "span_lookup")

                let child = await customSpan(name: "child", spanID: "span_child")
                #expect(child.traceID == "trace_scope")
                #expect(child.parentID == "span_lookup")
            }
        }

        #expect(getCurrentTrace() == nil)
        #expect(getCurrentSpan() == nil)
    }
}
