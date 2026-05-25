#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import ClinDeskAgents

public struct OpenAIResponsesModel: Model {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static var defaultModel: String {
        ProcessInfo.processInfo.environment["OPENAI_DEFAULT_MODEL"]?.lowercased() ?? "gpt-5.4-mini"
    }

    public var model: String
    public var apiKey: String
    public var baseURL: URL
    public var organization: String?
    public var project: String?
    public var transport: Transport

    public init(
        model: String = OpenAIResponsesModel.defaultModel,
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        organization: String? = ProcessInfo.processInfo.environment["OPENAI_ORG_ID"],
        project: String? = ProcessInfo.processInfo.environment["OPENAI_PROJECT_ID"],
        transport: Transport? = nil
    ) {
        self.model = model
        self.apiKey = apiKey ?? ""
        self.baseURL = baseURL
        self.organization = organization
        self.project = project
        self.transport = transport ?? Self.urlSessionTransport
    }

    public func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        guard !apiKey.isEmpty else {
            throw AgentsError.provider("OPENAI_API_KEY is required to use OpenAIResponsesModel.")
        }

        let url = baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organization {
            urlRequest.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project {
            urlRequest.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }

        urlRequest.httpBody = try JSONEncoder().encode(makePayload(for: request))
        let (data, response) = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            throw AgentsError.provider("OpenAI Responses API returned HTTP \(response.statusCode): \(body)")
        }

        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        return try Self.decodeResponse(json)
    }
}

public struct OpenAIProvider: ModelProvider {
    public var apiKey: String?
    public var baseURL: URL
    public var organization: String?
    public var project: String?

    public init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        organization: String? = ProcessInfo.processInfo.environment["OPENAI_ORG_ID"],
        project: String? = ProcessInfo.processInfo.environment["OPENAI_PROJECT_ID"]
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.organization = organization
        self.project = project
    }

    public func model(named name: String?) async throws -> any Model {
        OpenAIResponsesModel(
            model: name ?? OpenAIResponsesModel.defaultModel,
            apiKey: apiKey,
            baseURL: baseURL,
            organization: organization,
            project: project
        )
    }
}

private extension OpenAIResponsesModel {
    static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentsError.provider("OpenAI request did not return an HTTP response.")
        }
        return (data, http)
    }

    func makePayload<Context: Sendable>(for request: ModelRequest<Context>) -> JSONValue {
        var payload: [String: JSONValue] = [
            "model": .string(model),
            "input": .array(request.input.map(Self.encodeInputItem))
        ]

        if let instructions = request.instructions, !instructions.isEmpty {
            payload["instructions"] = .string(instructions)
        }
        if let maxOutputTokens = request.settings.maxOutputTokens {
            payload["max_output_tokens"] = .number(Double(maxOutputTokens))
        }
        if let temperature = request.settings.temperature {
            payload["temperature"] = .number(temperature)
        }
        if let topP = request.settings.topP {
            payload["top_p"] = .number(topP)
        }
        if let parallelToolCalls = request.settings.parallelToolCalls {
            payload["parallel_tool_calls"] = .bool(parallelToolCalls)
        }
        if let store = request.settings.store {
            payload["store"] = .bool(store)
        }
        if !request.settings.metadata.isEmpty {
            payload["metadata"] = .object(request.settings.metadata.mapValues(JSONValue.string))
        }
        if let previousResponseID = request.previousResponseID {
            payload["previous_response_id"] = .string(previousResponseID)
        }
        if let conversationID = request.conversationID {
            payload["conversation"] = .string(conversationID)
        }

        let functionTools = request.tools.map(Self.encodeTool)
        let handoffTools = request.handoffs.map(Self.encodeHandoff)
        let tools = functionTools + handoffTools
        if !tools.isEmpty {
            payload["tools"] = .array(tools)
            payload["tool_choice"] = .string("auto")
        }

        if let outputSchema = request.outputSchema {
            payload["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": "agent_output",
                    "schema": outputSchema,
                    "strict": true
                ]
            ]
        }

        return .object(payload)
    }

    static func encodeTool(_ descriptor: ToolDescriptor) -> JSONValue {
        [
            "type": "function",
            "name": .string(descriptor.name),
            "description": .string(descriptor.description),
            "parameters": descriptor.parameters,
            "strict": .bool(descriptor.strict)
        ]
    }

    static func encodeHandoff(_ descriptor: HandoffDescriptor) -> JSONValue {
        [
            "type": "function",
            "name": .string(descriptor.toolName),
            "description": .string(descriptor.description),
            "parameters": descriptor.inputSchema,
            "strict": true
        ]
    }

    static func encodeInputItem(_ item: ModelInputItem) -> JSONValue {
        switch item {
        case .message(let message):
            return [
                "type": "message",
                "role": .string(message.role.rawValue),
                "content": .array([
                    [
                        "type": .string(contentType(for: message.role)),
                        "text": .string(message.content)
                    ]
                ])
            ]
        case .functionCall(let call):
            return [
                "type": "function_call",
                "id": .string(call.id),
                "call_id": .string(call.callID),
                "name": .string(call.name),
                "arguments": .string(call.arguments.prettyPrinted())
            ]
        case .functionCallOutput(let output):
            return [
                "type": "function_call_output",
                "call_id": .string(output.callID),
                "output": .string(output.output.toolOutputString)
            ]
        case .reasoning(let value), .raw(let value):
            return value
        }
    }

    static func contentType(for role: AgentMessage.Role) -> String {
        switch role {
        case .assistant:
            return "output_text"
        default:
            return "input_text"
        }
    }

    static func decodeResponse(_ json: JSONValue) throws -> ModelResponse {
        guard let object = json.objectValue else {
            throw AgentsError.invalidModelResponse("Expected a JSON object.")
        }

        let id = object["id"]?.stringValue
        let outputValues: [JSONValue]
        if case .array(let values) = object["output"] {
            outputValues = values
        } else {
            outputValues = []
        }

        var output = try outputValues.map(decodeOutputItem)
        if output.isEmpty, let outputText = object["output_text"]?.stringValue, !outputText.isEmpty {
            output.append(.message(AgentMessage(role: .assistant, content: outputText)))
        }
        return ModelResponse(
            id: id,
            output: output,
            usage: decodeUsage(object["usage"]),
            raw: json
        )
    }

    static func decodeOutputItem(_ value: JSONValue) throws -> ModelOutputItem {
        guard let object = value.objectValue,
              let type = object["type"]?.stringValue
        else {
            return .raw(value)
        }

        switch type {
        case "message":
            let text = decodeMessageText(object["content"])
            let role = AgentMessage.Role(rawValue: object["role"]?.stringValue ?? "assistant") ?? .assistant
            return .message(AgentMessage(role: role, content: text))
        case "function_call":
            let name = object["name"]?.stringValue ?? ""
            let rawArguments = object["arguments"]?.stringValue ?? "{}"
            let arguments = decodeArguments(rawArguments)
            let call = FunctionCall(
                id: object["id"]?.stringValue ?? UUID().uuidString,
                callID: object["call_id"]?.stringValue ?? UUID().uuidString,
                name: name,
                arguments: arguments
            )
            return .functionCall(call)
        case "reasoning":
            return .reasoning(value)
        default:
            return .raw(value)
        }
    }

    static func decodeMessageText(_ content: JSONValue?) -> String {
        guard case .array(let parts) = content else {
            return content?.stringValue ?? ""
        }
        return parts.compactMap { part in
            part["text"]?.stringValue
        }.joined()
    }

    static func decodeArguments(_ string: String) -> JSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .string(string)
        }
        return value
    }

    static func decodeUsage(_ value: JSONValue?) -> TokenUsage? {
        guard let object = value?.objectValue else {
            return nil
        }
        let input = object["input_tokens"]?.intValue ?? 0
        let output = object["output_tokens"]?.intValue ?? 0
        let total = object["total_tokens"]?.intValue ?? input + output
        return TokenUsage(inputTokens: input, outputTokens: output, totalTokens: total)
    }
}

private extension JSONValue {
    var intValue: Int? {
        guard case .number(let number) = self else {
            return nil
        }
        return Int(number)
    }

    var toolOutputString: String {
        if case .string(let string) = self {
            return string
        }
        return prettyPrinted()
    }
}
