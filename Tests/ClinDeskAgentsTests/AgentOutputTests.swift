import Testing
import ClinDeskAgents

@Suite
struct AgentOutputTests {
    @Test
    func strictSchemaConvertsEmptySchemaToStrictObject() throws {
        #expect(try StrictSchema.ensureStrictJSONSchema([:]) == [
            "additionalProperties": false,
            "type": "object",
            "properties": [:],
            "required": []
        ])
    }

    @Test
    func strictSchemaRequiresAllObjectPropertiesAndRecurses() throws {
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "default": nil],
                "tags": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "label": ["type": "string"]
                        ]
                    ]
                ],
                "choice": [
                    "oneOf": [
                        ["type": "string"],
                        ["type": "number"]
                    ]
                ]
            ]
        ]

        let strict = try StrictSchema.ensureStrictJSONSchema(schema)

        #expect(strict["additionalProperties"] == .bool(false))
        #expect(strict["required"]?.arrayValue?.contains(.string("name")) == true)
        #expect(strict["required"]?.arrayValue?.contains(.string("tags")) == true)
        #expect(strict["required"]?.arrayValue?.contains(.string("choice")) == true)
        #expect(strict["properties"]?["name"]?["default"] == nil)
        #expect(strict["properties"]?["tags"]?["items"]?["additionalProperties"] == .bool(false))
        #expect(strict["properties"]?["tags"]?["items"]?["required"] == [.string("label")])
        #expect(strict["properties"]?["choice"]?["oneOf"] == nil)
        #expect(strict["properties"]?["choice"]?["anyOf"]?.arrayValue?.count == 2)
    }

    @Test
    func strictSchemaRejectsAdditionalPropertiesTrue() {
        let schema: JSONValue = [
            "type": "object",
            "additionalProperties": true,
            "properties": [:]
        ]

        #expect(throws: AgentsError.invalidRunConfig(
            "additionalProperties should not be set for object types. Use a non-strict schema if additional properties are required."
        )) {
            _ = try StrictSchema.ensureStrictJSONSchema(schema)
        }
    }

    @Test
    func agentOutputSchemaPreservesNonStrictSchema() throws {
        let schema: JSONValue = [
            "type": "object",
            "additionalProperties": true,
            "properties": [:]
        ]

        let outputSchema = try AgentOutputSchema(
            name: "LooseOutput",
            jsonSchema: schema,
            strictJSONSchema: false
        )

        #expect(outputSchema.name == "LooseOutput")
        #expect(outputSchema.jsonSchema == schema)
        #expect(outputSchema.strictJSONSchema == false)
    }

    @Test
    func plainTextOutputSchemaHasNoJSONSchema() throws {
        let outputSchema = AgentOutputSchema.plainText()

        #expect(outputSchema.name == "str")
        #expect(outputSchema.isPlainText)
        #expect(outputSchema.isStrictJSONSchema == false)
        #expect(throws: AgentsError.invalidRunConfig(
            "Output type is plain text, so no JSON schema is available."
        )) {
            _ = try outputSchema.schemaValue()
        }
    }

    @Test
    func nonObjectOutputSchemaCanBeWrappedWithResponseKey() throws {
        let outputSchema = try AgentOutputSchema(
            name: "Array<String>",
            jsonSchema: [
                "type": "array",
                "items": [
                    "type": "string"
                ]
            ],
            wrapNonObjectSchema: true
        )

        let expectedSchema: JSONValue = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                agentOutputWrapperKey: [
                    "type": "array",
                    "items": [
                        "type": "string"
                    ]
                ]
            ],
            "required": [
                .string(agentOutputWrapperKey)
            ]
        ]

        #expect(outputSchema.isPlainText == false)
        #expect(outputSchema.isWrapped)
        #expect(try outputSchema.schemaValue() == expectedSchema)
        let decoded = try outputSchema.validateJSON(
            [String].self,
            jsonString: #"{"response":["ready","set"]}"#
        )
        #expect(decoded == ["ready", "set"])
    }

    @Test
    func wrappedOutputSchemaRejectsMissingResponseKey() throws {
        let outputSchema = try AgentOutputSchema(
            name: "Int",
            jsonSchema: [
                "type": "integer"
            ],
            wrapNonObjectSchema: true
        )

        do {
            _ = try outputSchema.validateJSON(Int.self, jsonString: #"{"value":1}"#)
            Issue.record("Expected invalid structured output")
        } catch AgentsError.invalidStructuredOutput {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
