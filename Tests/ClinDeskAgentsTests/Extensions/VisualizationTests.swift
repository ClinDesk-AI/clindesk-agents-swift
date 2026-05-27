import Foundation
import Testing
import ClinDeskAgents

@Suite
struct VisualizationTests {
    @Test
    func getMainGraphIncludesAgentsToolsAndHandoffs() {
        let lookup = FunctionTool<Void>(name: "lookup", description: "Lookup.") { _, _ in
            .text("ok")
        }
        let booking = Agent<Void>(name: "Booking")
        let triage = Agent<Void>(
            name: "Triage",
            tools: [.function(lookup)],
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")]
        )

        let graph = AgentVisualization.getMainGraph(agent: triage)

        #expect(graph.contains("digraph G"))
        #expect(graph.contains(#""__start__" -> "Triage";"#))
        #expect(graph.contains(#""Triage" [label="Triage", shape=box"#))
        #expect(graph.contains(#""lookup" [label="lookup", shape=ellipse"#))
        #expect(graph.contains(#""Triage" -> "lookup" [style=dotted"#))
        #expect(graph.contains(#""lookup" -> "Triage" [style=dotted"#))
        #expect(graph.contains(#""Triage" -> "Booking";"#))
        #expect(graph.contains(#""Booking" -> "__end__";"#))
    }

    @Test
    func getMainGraphSkipsAlreadyVisitedAgents() {
        let root = Agent<Void>(name: "Root")
        let child = Agent<Void>(name: "Child", handoffs: [Handoff(to: root)])
        let graph = AgentVisualization.getMainGraph(agent: Agent<Void>(
            name: "Root",
            handoffs: [Handoff(to: child)]
        ))

        #expect(graph.components(separatedBy: #""Root" [label="Root""#).count == 2)
        #expect(graph.contains(#""Child" -> "Root";"#))
    }

    @Test
    func writeGraphWritesDotSource() throws {
        let agent = Agent<Void>(name: "Writer")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clindesk-agent-graph-\(UUID().uuidString).dot")
        defer { try? FileManager.default.removeItem(at: url) }

        try AgentVisualization.writeGraph(for: agent, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == AgentVisualization.getMainGraph(agent: agent))
    }
}
