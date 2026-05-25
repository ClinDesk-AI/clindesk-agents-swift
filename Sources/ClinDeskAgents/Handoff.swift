import Foundation

public struct HandoffDescriptor: Codable, Equatable, Sendable {
    public var toolName: String
    public var description: String
    public var inputSchema: JSONValue

    public init(toolName: String, description: String, inputSchema: JSONValue = .emptyObject) {
        self.toolName = toolName
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct Handoff<Context: Sendable>: Sendable {
    public typealias Enabled = @Sendable (RunContext<Context>) async -> Bool
    public typealias InputFilter = HandoffInputFilter

    public var descriptor: HandoffDescriptor
    public var isEnabled: Enabled
    public var inputFilter: InputFilter?
    private let resolveAgent: @Sendable () -> Agent<Context>

    public var agent: Agent<Context> {
        resolveAgent()
    }

    public init(
        to agent: Agent<Context>,
        toolName: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue = .emptyObject,
        isEnabled: @escaping Enabled = { _ in true },
        inputFilter: InputFilter? = nil
    ) {
        self.descriptor = HandoffDescriptor(
            toolName: toolName ?? Self.defaultToolName(for: agent.name),
            description: description ?? agent.handoffDescription ?? "Transfer to \(agent.name).",
            inputSchema: inputSchema
        )
        self.isEnabled = isEnabled
        self.inputFilter = inputFilter
        self.resolveAgent = { agent }
    }

    public static func defaultToolName(for agentName: String) -> String {
        let allowed = agentName
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                return "_"
            }
        let collapsed = String(allowed).split(separator: "_").joined(separator: "_")
        return "transfer_to_\(collapsed.isEmpty ? "agent" : collapsed)"
    }
}
