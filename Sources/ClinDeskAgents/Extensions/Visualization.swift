import Foundation

public enum AgentVisualization {
    public static func getMainGraph<Context: Sendable>(agent: Agent<Context>) -> String {
        var parts: [String] = [
            """

                digraph G {
                    graph [splines=true];
                    node [fontname="Arial"];
                    edge [penwidth=1.5];
            """
        ]
        var visitedNodes = Set<String>()
        parts.append(getAllNodes(agent: agent, visited: &visitedNodes))
        var visitedEdges = Set<String>()
        parts.append(getAllEdges(agent: agent, visited: &visitedEdges))
        parts.append("}")
        return parts.joined()
    }

    public static func getAllNodes<Context: Sendable>(
        agent: Agent<Context>,
        parent: Agent<Context>? = nil
    ) -> String {
        var visited = Set<String>()
        return getAllNodes(agent: agent, parent: parent, visited: &visited)
    }

    public static func getAllEdges<Context: Sendable>(
        agent: Agent<Context>,
        parent: Agent<Context>? = nil
    ) -> String {
        var visited = Set<String>()
        return getAllEdges(agent: agent, parent: parent, visited: &visited)
    }

    public static func writeGraph<Context: Sendable>(
        for agent: Agent<Context>,
        to url: URL
    ) throws {
        try getMainGraph(agent: agent).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func getAllNodes<Context: Sendable>(
        agent: Agent<Context>,
        parent: Agent<Context>? = nil,
        visited: inout Set<String>
    ) -> String {
        guard !visited.contains(agent.name) else {
            return ""
        }
        visited.insert(agent.name)

        var parts: [String] = []
        if parent == nil {
            parts.append(
                #""__start__" [label="__start__", shape=ellipse, style=filled, fillcolor=lightblue, width=0.5, height=0.3];"__end__" [label="__end__", shape=ellipse, style=filled, fillcolor=lightblue, width=0.5, height=0.3];"#
            )
            parts.append(
                #""\#(dotEscaped(agent.name))" [label="\#(dotEscaped(agent.name))", shape=box, style=filled, fillcolor=lightyellow, width=1.5, height=0.8];"#
            )
        }

        for tool in agent.tools {
            let name = dotEscaped(tool.name)
            parts.append(
                #""\#(name)" [label="\#(name)", shape=ellipse, style=filled, fillcolor=lightgreen, width=0.5, height=0.3];"#
            )
        }

        for handoff in agent.handoffs {
            let target = handoff.agent
            if !visited.contains(target.name) {
                let targetName = dotEscaped(target.name)
                parts.append(
                    #""\#(targetName)" [label="\#(targetName)", shape=box, style=filled, style=rounded, fillcolor=lightyellow, width=1.5, height=0.8];"#
                )
            }
            parts.append(getAllNodes(agent: target, parent: agent, visited: &visited))
        }

        return parts.joined()
    }

    private static func getAllEdges<Context: Sendable>(
        agent: Agent<Context>,
        parent: Agent<Context>? = nil,
        visited: inout Set<String>
    ) -> String {
        guard !visited.contains(agent.name) else {
            return ""
        }
        visited.insert(agent.name)

        let agentName = dotEscaped(agent.name)
        var parts: [String] = []
        if parent == nil {
            parts.append(#""__start__" -> "\#(agentName)";"#)
        }

        for tool in agent.tools {
            let toolName = dotEscaped(tool.name)
            parts.append("""

                    "\(agentName)" -> "\(toolName)" [style=dotted, penwidth=1.5];
                    "\(toolName)" -> "\(agentName)" [style=dotted, penwidth=1.5];
            """)
        }

        for handoff in agent.handoffs {
            let target = handoff.agent
            let targetName = dotEscaped(target.name)
            parts.append("""

                        "\(agentName)" -> "\(targetName)";
            """)
            parts.append(getAllEdges(agent: target, parent: agent, visited: &visited))
        }

        if agent.handoffs.isEmpty {
            parts.append(#""\#(agentName)" -> "__end__";"#)
        }

        return parts.joined()
    }

    private static func dotEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
