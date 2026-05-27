import Foundation

public let agentOutputWrapperKey = "response"

public struct AgentOutputSchema: Equatable, Sendable {
    public var name: String
    public var jsonSchema: JSONValue
    public var strictJSONSchema: Bool
    public var isPlainText: Bool
    public var isWrapped: Bool

    public init(
        name: String,
        jsonSchema: JSONValue,
        strictJSONSchema: Bool = true,
        wrapNonObjectSchema: Bool = false
    ) throws {
        self.name = name
        self.strictJSONSchema = strictJSONSchema
        self.isPlainText = false
        self.isWrapped = wrapNonObjectSchema && !Self.isObjectSchema(jsonSchema)
        let schema = isWrapped ? Self.wrappedSchema(jsonSchema) : jsonSchema
        self.jsonSchema = strictJSONSchema
            ? try StrictSchema.ensureStrictJSONSchema(schema)
            : schema
    }

    private init(name: String, jsonSchema: JSONValue, strictJSONSchema: Bool, isPlainText: Bool, isWrapped: Bool) {
        self.name = name
        self.jsonSchema = jsonSchema
        self.strictJSONSchema = strictJSONSchema
        self.isPlainText = isPlainText
        self.isWrapped = isWrapped
    }

    public static func plainText(name: String = "str") -> AgentOutputSchema {
        AgentOutputSchema(
            name: name,
            jsonSchema: ["type": "string"],
            strictJSONSchema: false,
            isPlainText: true,
            isWrapped: false
        )
    }

    public var isStrictJSONSchema: Bool {
        strictJSONSchema
    }

    public func schemaValue() throws -> JSONValue {
        guard !isPlainText else {
            throw AgentsError.invalidRunConfig("Output type is plain text, so no JSON schema is available.")
        }
        return jsonSchema
    }

    public func validateJSON<Output: Decodable>(
        _ outputType: Output.Type,
        jsonString: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        if isWrapped {
            return try StructuredOutput.decodeWrapped(outputType, from: jsonString, decoder: decoder)
        }
        return try StructuredOutput.decode(outputType, from: jsonString, decoder: decoder)
    }

    private static func isObjectSchema(_ schema: JSONValue) -> Bool {
        schema.objectValue?["type"]?.stringValue == "object"
    }

    private static func wrappedSchema(_ schema: JSONValue) -> JSONValue {
        [
            "type": "object",
            "properties": [
                agentOutputWrapperKey: schema
            ],
            "required": [
                .string(agentOutputWrapperKey)
            ]
        ]
    }
}

private struct WrappedStructuredOutput<Value: Decodable>: Decodable {
    var response: Value
}

public enum StructuredOutput {
    public static func decode<Output: Decodable>(
        _ outputType: Output.Type,
        from rawOutput: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentsError.invalidStructuredOutput("Final output was not valid UTF-8.")
        }
        do {
            return try decoder.decode(outputType, from: data)
        } catch {
            throw AgentsError.invalidStructuredOutput(error.localizedDescription)
        }
    }

    public static func decodeWrapped<Output: Decodable>(
        _ outputType: Output.Type,
        from rawOutput: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        let wrapped = try decode(WrappedStructuredOutput<Output>.self, from: rawOutput, decoder: decoder)
        return wrapped.response
    }
}
