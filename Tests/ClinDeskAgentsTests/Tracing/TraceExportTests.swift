import Testing
import ClinDeskAgents

@Suite
struct TraceExportTests {
    @Test
    func traceExportUsesUpstreamShape() throws {
        let trace = Trace(
            id: "trace_123",
            workflowName: "Checkout",
            groupID: "group_456",
            metadata: ["tenant": "clinic"]
        )
        let exported = try #require(trace.export())

        #expect(trace.traceID == "trace_123")
        #expect(trace.name == "Checkout")
        #expect(exported == [
            "object": "trace",
            "id": "trace_123",
            "workflow_name": "Checkout",
            "group_id": "group_456",
            "metadata": ["tenant": "clinic"]
        ])
        #expect(trace.toJSON() == exported)
    }

    @Test
    func noOpTraceDoesNotExport() {
        #expect(Trace.noOp().export() == nil)
    }

    @Test
    func tracingIDsUseUpstreamPrefixesAndLengths() {
        let traceID = TracingIDs.genTraceID()
        let spanID = TracingIDs.genSpanID()
        let groupID = TracingIDs.genGroupID()

        #expect(traceID.hasPrefix("trace_"))
        #expect(traceID.count == "trace_".count + 32)
        #expect(spanID.hasPrefix("span_"))
        #expect(spanID.count == "span_".count + 24)
        #expect(groupID.hasPrefix("group_"))
        #expect(groupID.count == "group_".count + 24)
    }
}
