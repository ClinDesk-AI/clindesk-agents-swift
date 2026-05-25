import Foundation

public struct AgentMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case developer
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct FunctionCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String = UUID().uuidString, callID: String = UUID().uuidString, name: String, arguments: JSONValue) {
        self.id = id
        self.callID = callID
        self.name = name
        self.arguments = arguments
    }
}

public struct FunctionCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: JSONValue

    public init(callID: String, output: JSONValue) {
        self.callID = callID
        self.output = output
    }
}

public enum ModelInputItem: Codable, Equatable, Sendable {
    case message(AgentMessage)
    case functionCall(FunctionCall)
    case functionCallOutput(FunctionCallOutput)
    case reasoning(JSONValue)
    case raw(JSONValue)
}

public enum ModelOutputItem: Codable, Equatable, Sendable {
    case message(AgentMessage)
    case functionCall(FunctionCall)
    case reasoning(JSONValue)
    case raw(JSONValue)
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, totalTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct ModelResponse: Equatable, Sendable {
    public var id: String?
    public var output: [ModelOutputItem]
    public var usage: TokenUsage?
    public var raw: JSONValue?

    public init(id: String? = nil, output: [ModelOutputItem], usage: TokenUsage? = nil, raw: JSONValue? = nil) {
        self.id = id
        self.output = output
        self.usage = usage
        self.raw = raw
    }

    public var outputText: String {
        output.compactMap { item in
            if case .message(let message) = item {
                return message.content
            }
            return nil
        }.joined(separator: "\n")
    }

    public var functionCalls: [FunctionCall] {
        output.compactMap { item in
            if case .functionCall(let call) = item {
                return call
            }
            return nil
        }
    }
}
