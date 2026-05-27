import Foundation

public enum ToolOriginType: String, Codable, Equatable, Sendable {
    case function
    case agentAsTool = "agent_as_tool"
}

public struct ToolOrigin: Codable, Equatable, Sendable {
    public var type: ToolOriginType
    public var agentName: String?
    public var agentToolName: String?

    public init(
        type: ToolOriginType,
        agentName: String? = nil,
        agentToolName: String? = nil
    ) {
        self.type = type
        self.agentName = agentName
        self.agentToolName = agentToolName
    }

    public func toDictionary() -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "type": .string(type.rawValue)
        ]
        if let agentName {
            payload["agent_name"] = .string(agentName)
        }
        if let agentToolName {
            payload["agent_tool_name"] = .string(agentToolName)
        }
        return payload
    }

    public init?(dictionary: [String: JSONValue]) {
        guard let rawType = dictionary["type"]?.stringValue,
              let type = ToolOriginType(rawValue: rawType)
        else {
            return nil
        }
        self.init(
            type: type,
            agentName: dictionary["agent_name"]?.stringValue,
            agentToolName: dictionary["agent_tool_name"]?.stringValue
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case agentName = "agent_name"
        case agentToolName = "agent_tool_name"
    }
}
