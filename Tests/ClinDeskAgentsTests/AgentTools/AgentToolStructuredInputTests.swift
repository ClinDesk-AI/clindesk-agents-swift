import Testing
import ClinDeskAgents

@Suite
struct AgentToolStructuredInputTests {
    @Test
    func agentAsToolBuildsStructuredInputFromCustomParameterSchema() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Translator", model: childModel)
        let parameters: JSONValue = [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "Text to translate"
                ],
                "target": [
                    "type": "string",
                    "description": "Target language"
                ]
            ],
            "required": ["text", "target"],
            "additionalProperties": false
        ]
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_translate",
                    name: "translator",
                    arguments: ["text": "hola", "target": "en"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool(parameters: parameters)],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        guard case .message(let message)? = childRequests.first?.input.first else {
            Issue.record("Expected structured input message")
            return
        }
        #expect(message.content.contains("Structured Input Data"))
        #expect(message.content.contains("Input Schema Summary"))
        #expect(message.content.contains("text (string, required)"))
        #expect(message.content.contains("Text to translate"))
        #expect(message.content.contains("target (string, required)"))
        #expect(message.content.contains("Target language"))
        #expect(message.content.contains(#""text":"hola""#))
        #expect(message.content.contains(#""target":"en""#))
    }

    @Test
    func agentAsToolSupportsCustomStructuredInputBuilder() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Builder", model: childModel)
        let parameters: JSONValue = [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "Text to translate"
                ]
            ],
            "required": ["text"],
            "additionalProperties": false
        ]
        let customInput = [ModelInputItem.message(AgentMessage(role: .user, content: "custom input"))]
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_builder",
                    name: "builder",
                    arguments: ["text": "hola"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(parameters: parameters, inputBuilder: { options in
                    #expect(options.params == ["text": "hola"])
                    #expect(options.summary?.contains("text (string, required)") == true)
                    #expect(options.jsonSchema == nil)
                    return .items(customInput)
                })
            ],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        #expect(childRequests.first?.input == customInput)
    }

    @Test
    func agentAsToolCanIncludeFullInputSchemaForStructuredInput() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Schema", model: childModel)
        let parameters: JSONValue = [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "Text to translate"
                ]
            ],
            "required": ["text"],
            "additionalProperties": false
        ]
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_schema",
                    name: "schema",
                    arguments: ["text": "hola"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool(parameters: parameters, includeInputSchema: true)],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        guard case .message(let message)? = childRequests.first?.input.first else {
            Issue.record("Expected schema input message")
            return
        }
        #expect(message.content.contains("Input JSON Schema"))
        #expect(message.content.contains(#""properties""#))
        #expect(message.content.contains(#""text""#))
    }

    @Test
    func agentAsToolIgnoresIncludedInputSchemaWithoutCustomParameters() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "plain input"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [child.asTool(includeInputSchema: true)],
            model: parentModel
        )

        _ = try await Runner.run(agent: parent, input: "Run")

        let childRequests = await childModel.requests()
        #expect(childRequests.first?.input == [
            .message(AgentMessage(role: .user, content: "plain input"))
        ])
    }
}
