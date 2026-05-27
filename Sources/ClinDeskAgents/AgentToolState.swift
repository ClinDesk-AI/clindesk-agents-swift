import Foundation

struct AgentToolRunResultSignature: Hashable, Sendable {
    var scopeID: String
    var callID: String
    var name: String
    var namespace: String?
    var arguments: String

    init(call: FunctionCall, scopeID: String) {
        self.scopeID = scopeID
        self.callID = call.callID
        self.name = call.name
        self.namespace = call.namespace
        self.arguments = call.arguments.prettyPrinted()
    }
}

actor AgentToolStateStore {
    static let shared = AgentToolStateStore()

    private var runResults: [AgentToolRunResultSignature: RunResult] = [:]

    func record(_ runResult: RunResult, for call: FunctionCall, scopeID: String) {
        runResults[AgentToolRunResultSignature(call: call, scopeID: scopeID)] = runResult
    }

    func peek(for call: FunctionCall, scopeID: String) -> RunResult? {
        runResults[AgentToolRunResultSignature(call: call, scopeID: scopeID)]
    }

    func consume(for call: FunctionCall, scopeID: String) -> RunResult? {
        runResults.removeValue(forKey: AgentToolRunResultSignature(call: call, scopeID: scopeID))
    }
}

enum AgentToolState {
    static func record(_ runResult: RunResult, for call: FunctionCall, scopeID: String) async {
        await AgentToolStateStore.shared.record(runResult, for: call, scopeID: scopeID)
    }

    static func peek(call: FunctionCall, scopeID: String) async -> RunResult? {
        await AgentToolStateStore.shared.peek(for: call, scopeID: scopeID)
    }

    static func consume(call: FunctionCall, scopeID: String) async -> RunResult? {
        await AgentToolStateStore.shared.consume(for: call, scopeID: scopeID)
    }
}
