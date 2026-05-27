public struct Prompt: Equatable, Sendable {
    public var id: String
    public var version: String?
    public var variables: [String: JSONValue]

    public init(
        id: String,
        version: String? = nil,
        variables: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.version = version
        self.variables = variables
    }
}

public struct GenerateDynamicPromptData<Context: Sendable>: Sendable {
    public var context: RunContext<Context>
    public var agent: Agent<Context>

    public init(context: RunContext<Context>, agent: Agent<Context>) {
        self.context = context
        self.agent = agent
    }
}

public enum AgentPrompt<Context: Sendable>: Sendable {
    public typealias Builder = @Sendable (GenerateDynamicPromptData<Context>) async throws -> Prompt

    case prompt(Prompt)
    case dynamic(Builder)

    public func resolve(context: RunContext<Context>, agent: Agent<Context>) async throws -> Prompt {
        switch self {
        case .prompt(let prompt):
            return prompt
        case .dynamic(let builder):
            return try await builder(GenerateDynamicPromptData(context: context, agent: agent))
        }
    }
}
