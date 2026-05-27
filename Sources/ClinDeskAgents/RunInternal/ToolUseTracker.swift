import Foundation

struct AgentToolUseTracker<Context: Sendable>: Sendable {
    private var agentIdentityToTools: [String: Set<String>]
    private var agentIdentityToName: [String: String]
    private var hydratedAgentNameToTools: [String: Set<String>]

    init(snapshot: [String: [String]] = [:]) {
        self.agentIdentityToTools = [:]
        self.agentIdentityToName = [:]
        self.hydratedAgentNameToTools = snapshot.mapValues(Set.init)
    }

    func hasUsedTools(_ agent: Agent<Context>) -> Bool {
        if let tools = agentIdentityToTools[agent.identityKey], !tools.isEmpty {
            return true
        }
        return !(hydratedAgentNameToTools[agent.name]?.isEmpty ?? true)
    }

    mutating func recordFunctionToolResults(
        _ results: [ToolRunResult],
        agent: Agent<Context>
    ) {
        addToolUse(
            agent: agent,
            toolNames: results.map { $0.call.qualifiedName }
        )
    }

    mutating func recordCustomToolResults(
        _ results: [CustomToolRunResult],
        agent: Agent<Context>
    ) {
        addToolUse(
            agent: agent,
            toolNames: results.map { $0.call.name }
        )
    }

    mutating func addToolUse(agent: Agent<Context>, toolNames: [String]) {
        guard !toolNames.isEmpty else {
            return
        }
        var identityNames = agentIdentityToTools[agent.identityKey] ?? []
        identityNames.formUnion(toolNames)
        agentIdentityToTools[agent.identityKey] = identityNames
        agentIdentityToName[agent.identityKey] = agent.name
    }

    func snapshot() -> [String: [String]] {
        var snapshot = hydratedAgentNameToTools
        for (identity, toolNames) in agentIdentityToTools {
            let name = agentIdentityToName[identity] ?? identity
            snapshot[name, default: []].formUnion(toolNames)
        }
        return snapshot.mapValues { $0.sorted() }
    }
}
