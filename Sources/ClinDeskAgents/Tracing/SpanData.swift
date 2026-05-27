import Foundation

public protocol SpanData: Sendable {
    var type: String { get }
    var metadata: [String: JSONValue]? { get }
    func export() -> [String: JSONValue]
}

public extension SpanData {
    var metadata: [String: JSONValue]? {
        nil
    }
}

public struct AgentSpanData: SpanData, Equatable {
    public var name: String
    public var handoffs: [String]?
    public var tools: [String]?
    public var outputType: String?
    public var metadata: [String: JSONValue]?

    public init(
        name: String,
        handoffs: [String]? = nil,
        tools: [String]? = nil,
        outputType: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.handoffs = handoffs
        self.tools = tools
        self.outputType = outputType
        self.metadata = metadata
    }

    public var type: String { "agent" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "name": .string(name),
            "handoffs": jsonArray(handoffs),
            "tools": jsonArray(tools),
            "output_type": outputType.map(JSONValue.string) ?? .null
        ]
    }
}

public struct TaskSpanData: SpanData, Equatable {
    public var name: String
    public var usage: [String: JSONValue]?
    public var metadata: [String: JSONValue]?

    public init(
        name: String,
        usage: [String: JSONValue]? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.usage = usage
        self.metadata = metadata
    }

    public var type: String { "task" }

    public func export() -> [String: JSONValue] {
        var data: [String: JSONValue] = [
            "sdk_span_type": .string(type),
            "name": .string(name)
        ]
        if let usage {
            data["usage"] = .object(usage)
        }
        return [
            "type": "custom",
            "name": .string(type),
            "data": .object(data)
        ]
    }
}

public struct TurnSpanData: SpanData, Equatable {
    public var turn: Int
    public var agentName: String
    public var usage: [String: JSONValue]?
    public var metadata: [String: JSONValue]?

    public init(
        turn: Int,
        agentName: String,
        usage: [String: JSONValue]? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.turn = turn
        self.agentName = agentName
        self.usage = usage
        self.metadata = metadata
    }

    public var type: String { "turn" }

    public func export() -> [String: JSONValue] {
        var data: [String: JSONValue] = [
            "sdk_span_type": .string(type),
            "turn": .number(Double(turn)),
            "agent_name": .string(agentName)
        ]
        if let usage {
            data["usage"] = .object(usage)
        }
        return [
            "type": "custom",
            "name": .string(type),
            "data": .object(data)
        ]
    }
}

public struct FunctionSpanData: SpanData, Equatable {
    public var name: String
    public var input: String?
    public var output: String?

    public init(
        name: String,
        input: String? = nil,
        output: String? = nil
    ) {
        self.name = name
        self.input = input
        self.output = output
    }

    public var type: String { "function" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "name": .string(name),
            "input": input.map(JSONValue.string) ?? .null,
            "output": output.map(JSONValue.string) ?? .null
        ]
    }
}

public struct GenerationSpanData: SpanData, Equatable {
    public var input: [[String: JSONValue]]?
    public var output: [[String: JSONValue]]?
    public var model: String?
    public var modelConfig: [String: JSONValue]?
    public var usage: [String: JSONValue]?

    public init(
        input: [[String: JSONValue]]? = nil,
        output: [[String: JSONValue]]? = nil,
        model: String? = nil,
        modelConfig: [String: JSONValue]? = nil,
        usage: [String: JSONValue]? = nil
    ) {
        self.input = input
        self.output = output
        self.model = model
        self.modelConfig = modelConfig
        self.usage = usage
    }

    public var type: String { "generation" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "input": jsonObjectArray(input),
            "output": jsonObjectArray(output),
            "model": model.map(JSONValue.string) ?? .null,
            "model_config": modelConfig.map(JSONValue.object) ?? .null,
            "usage": usage.map(JSONValue.object) ?? .null
        ]
    }
}

public struct ResponseSpanData: SpanData, Equatable {
    public var responseID: String?
    public var input: JSONValue?
    public var usage: [String: JSONValue]?

    public init(
        responseID: String? = nil,
        input: JSONValue? = nil,
        usage: [String: JSONValue]? = nil
    ) {
        self.responseID = responseID
        self.input = input
        self.usage = usage
    }

    public var type: String { "response" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "response_id": responseID.map(JSONValue.string) ?? .null,
            "usage": usage.map(JSONValue.object) ?? .null
        ]
    }
}

public struct HandoffSpanData: SpanData, Equatable {
    public var fromAgent: String?
    public var toAgent: String?

    public init(fromAgent: String? = nil, toAgent: String? = nil) {
        self.fromAgent = fromAgent
        self.toAgent = toAgent
    }

    public var type: String { "handoff" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "from_agent": fromAgent.map(JSONValue.string) ?? .null,
            "to_agent": toAgent.map(JSONValue.string) ?? .null
        ]
    }
}

public struct CustomSpanData: SpanData, Equatable {
    public var name: String
    public var data: [String: JSONValue]

    public init(name: String, data: [String: JSONValue]) {
        self.name = name
        self.data = data
    }

    public var type: String { "custom" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "name": .string(name),
            "data": .object(data)
        ]
    }
}

public struct GuardrailSpanData: SpanData, Equatable {
    public var name: String
    public var triggered: Bool

    public init(name: String, triggered: Bool = false) {
        self.name = name
        self.triggered = triggered
    }

    public var type: String { "guardrail" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "name": .string(name),
            "triggered": .bool(triggered)
        ]
    }
}

public struct TranscriptionSpanData: SpanData, Equatable {
    public var input: String?
    public var inputFormat: String?
    public var output: String?
    public var model: String?
    public var modelConfig: [String: JSONValue]?

    public init(
        input: String? = nil,
        inputFormat: String? = "pcm",
        output: String? = nil,
        model: String? = nil,
        modelConfig: [String: JSONValue]? = nil
    ) {
        self.input = input
        self.inputFormat = inputFormat
        self.output = output
        self.model = model
        self.modelConfig = modelConfig
    }

    public var type: String { "transcription" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "input": .object([
                "data": .string(input ?? ""),
                "format": inputFormat.map(JSONValue.string) ?? .null
            ]),
            "output": output.map(JSONValue.string) ?? .null,
            "model": model.map(JSONValue.string) ?? .null,
            "model_config": modelConfig.map(JSONValue.object) ?? .null
        ]
    }
}

public struct SpeechSpanData: SpanData, Equatable {
    public var input: String?
    public var output: String?
    public var outputFormat: String?
    public var model: String?
    public var modelConfig: [String: JSONValue]?
    public var firstContentAt: String?

    public init(
        input: String? = nil,
        output: String? = nil,
        outputFormat: String? = "pcm",
        model: String? = nil,
        modelConfig: [String: JSONValue]? = nil,
        firstContentAt: String? = nil
    ) {
        self.input = input
        self.output = output
        self.outputFormat = outputFormat
        self.model = model
        self.modelConfig = modelConfig
        self.firstContentAt = firstContentAt
    }

    public var type: String { "speech" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "input": input.map(JSONValue.string) ?? .null,
            "output": .object([
                "data": .string(output ?? ""),
                "format": outputFormat.map(JSONValue.string) ?? .null
            ]),
            "model": model.map(JSONValue.string) ?? .null,
            "model_config": modelConfig.map(JSONValue.object) ?? .null,
            "first_content_at": firstContentAt.map(JSONValue.string) ?? .null
        ]
    }
}

public struct SpeechGroupSpanData: SpanData, Equatable {
    public var input: String?

    public init(input: String? = nil) {
        self.input = input
    }

    public var type: String { "speech_group" }

    public func export() -> [String: JSONValue] {
        [
            "type": .string(type),
            "input": input.map(JSONValue.string) ?? .null
        ]
    }
}

private func jsonArray(_ values: [String]?) -> JSONValue {
    guard let values else {
        return .null
    }
    return .array(values.map(JSONValue.string))
}

private func jsonObjectArray(_ values: [[String: JSONValue]]?) -> JSONValue {
    guard let values else {
        return .null
    }
    return .array(values.map(JSONValue.object))
}
