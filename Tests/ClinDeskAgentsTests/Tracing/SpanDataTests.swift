import Foundation
import Testing
import ClinDeskAgents

@Suite
struct SpanDataTests {
    @Test
    func agentSpanDataExportsUpstreamShape() {
        let data = AgentSpanData(
            name: "Assistant",
            handoffs: ["Human"],
            tools: ["lookup"],
            outputType: "string"
        )

        #expect(data.export() == [
            "type": "agent",
            "name": "Assistant",
            "handoffs": ["Human"],
            "tools": ["lookup"],
            "output_type": "string"
        ])
    }

    @Test
    func taskAndTurnSpanDataExportAsCustomSpans() {
        #expect(TaskSpanData(name: "run", usage: ["requests": 1]).export() == [
            "type": "custom",
            "name": "task",
            "data": [
                "sdk_span_type": "task",
                "name": "run",
                "usage": ["requests": 1]
            ]
        ])

        #expect(TurnSpanData(turn: 2, agentName: "Assistant").export() == [
            "type": "custom",
            "name": "turn",
            "data": [
                "sdk_span_type": "turn",
                "turn": 2,
                "agent_name": "Assistant"
            ]
        ])
    }

    @Test
    func toolAndHandoffSpanDataExportUpstreamKeys() {
        #expect(FunctionSpanData(name: "lookup", input: "{}", output: "ok").export() == [
            "type": "function",
            "name": "lookup",
            "input": "{}",
            "output": "ok"
        ])

        #expect(HandoffSpanData(fromAgent: "Assistant", toAgent: "Human").export() == [
            "type": "handoff",
            "from_agent": "Assistant",
            "to_agent": "Human"
        ])

        #expect(GuardrailSpanData(name: "safety", triggered: true).export() == [
            "type": "guardrail",
            "name": "safety",
            "triggered": true
        ])
    }

    @Test
    func spanExportIncludesUpstreamWrapperAndRoutedMetadata() async throws {
        var span = Span(
            spanData: AgentSpanData(
                name: "Assistant",
                metadata: ["agent_harness_id": "span-value", "tenant": "clinic"]
            ),
            traceID: "trace_123",
            spanID: "span_123",
            parentID: "span_parent",
            traceMetadata: ["agent_harness_id": "trace-value"]
        )
        await span.start(at: Date(timeIntervalSince1970: 0))
        await span.finish(at: Date(timeIntervalSince1970: 1))
        span.setError(SpanError(message: "failed", data: ["code": "E_TEST"]))

        let payload = try #require(span.export())
        #expect(payload["object"] == "trace.span")
        #expect(payload["id"] == "span_123")
        #expect(payload["trace_id"] == "trace_123")
        #expect(payload["parent_id"] == "span_parent")
        #expect(payload["span_data"]?["type"] == "agent")
        #expect(payload["error"]?["message"] == "failed")
        #expect(payload["metadata"] == [
            "agent_harness_id": "trace-value",
            "tenant": "clinic"
        ])
    }

    @Test
    func noOpSpanDoesNotExport() {
        let span = Span.noOp(spanData: FunctionSpanData(name: "lookup"))

        #expect(span.export() == nil)
        #expect(span.isNoOp)
    }
}
