import Testing
import ClinDeskAgents

@Suite
struct TraceStateTests {
    @Test
    func traceStateFromTracePersistsTraceFields() throws {
        let trace = Trace(
            id: "trace_123",
            workflowName: "Checkout",
            groupID: "group_456",
            metadata: ["tenant": "clinic"]
        )

        let state = try #require(TraceState.fromTrace(trace))

        #expect(state.traceID == "trace_123")
        #expect(state.workflowName == "Checkout")
        #expect(state.groupID == "group_456")
        #expect(state.metadata == ["tenant": "clinic"])
    }

    @Test
    func traceStateFromJSONAcceptsTraceIDAliasesAndPreservesExtraFields() throws {
        let state = try #require(TraceState.fromJSON([
            "object": "trace",
            "trace_id": "trace_alias",
            "workflow_name": "Workflow",
            "metadata": ["tenant": "clinic"],
            "custom": ["value": 1]
        ]))

        let json = try #require(state.toJSON())
        #expect(state.traceID == "trace_alias")
        #expect(state.objectType == "trace")
        #expect(json["id"] == "trace_alias")
        #expect(json["trace_id"] == nil)
        #expect(json["custom"] == ["value": 1])
    }

    @Test
    func emptyTraceStateDoesNotSerialize() {
        #expect(TraceState().toJSON() == nil)
        #expect(TraceState.fromJSON(nil) == nil)
        #expect(TraceState.fromJSON([:]) == nil)
    }

    @Test
    func reattachTraceBuildsTraceWithoutEmittingLifecycle() throws {
        let state = TraceState(
            traceID: "trace_resume",
            workflowName: nil,
            groupID: "group_resume",
            metadata: ["tenant": "clinic"]
        )

        let trace = try #require(reattachTrace(from: state))

        #expect(trace.traceID == "trace_resume")
        #expect(trace.workflowName == "Agent workflow")
        #expect(trace.groupID == "group_resume")
        #expect(trace.metadata == ["tenant": "clinic"])
    }
}
