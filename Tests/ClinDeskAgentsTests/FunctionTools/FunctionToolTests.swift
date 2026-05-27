import Testing
import ClinDeskAgents

@Suite
struct FunctionToolTests {
    @Test
    func runsFunctionToolAndFeedsResultBackToModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_weather", name: "weather", arguments: ["city": "Cancun"]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "It is sunny in Cancun."))
            ])
        ])

        struct WeatherInput: Decodable, Sendable {
            let city: String
        }

        let weather = FunctionTool<Void>(
            name: "weather",
            description: "Get the weather.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string"]
                ],
                "required": ["city"],
                "additionalProperties": false
            ]
        ) { (_: ToolContext<Void>, input: WeatherInput) in
            .json(["forecast": .string("sunny"), "city": .string(input.city)])
        }

        let agent = Agent<Void>(name: "Weather", tools: [weather], model: model)
        let result = try await Runner.run(agent: agent, input: "Weather?")

        #expect(result.finalOutput == "It is sunny in Cancun.")
        #expect(result.newItems.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_weather"
            }
            return false
        })
    }

    @Test
    func toolContextExposesInvocationMetadataAndActiveAgent() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_lookup",
                    name: "lookup_account",
                    namespace: "crm",
                    arguments: ["customer_id": "cus_123"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let contextValues = StringRecorder()
        let lookup = FunctionTool<Void>(
            name: "lookup_account",
            description: "Lookup an account.",
            parameters: ["type": "object"]
        ) { context, arguments in
            #expect(context.toolName == "lookup_account")
            #expect(context.toolCallID == "call_lookup")
            #expect(context.toolArguments == arguments)
            #expect(context.rawToolArguments == #"{"customer_id":"cus_123"}"#)
            #expect(context.toolNamespace == "crm")
            #expect(context.qualifiedToolName == "crm.lookup_account")
            #expect(context.agent?.name == "Assistant")
            #expect(context.runConfig?.modelSettings?.maxOutputTokens == 42)
            await contextValues.append(context.qualifiedToolName)
            return .text("account")
        }
        let tools: [FunctionTool<Void>] = try toolNamespace(
            name: "crm",
            description: "CRM tools",
            tools: [lookup]
        )
        let agent = Agent<Void>(name: "Assistant", tools: tools, model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Lookup",
            runConfig: RunConfig<Void>(modelSettings: ModelSettings(maxOutputTokens: 42))
        )

        #expect(await contextValues.all() == ["crm.lookup_account"])
    }

    @Test
    func typedRunFunctionToolContextUsesPublicAgent() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: #"{"answer":"Done"}"#))
            ])
        ])
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"]
            ]
        ]
        let sawOutputSchema = StringRecorder()
        let lookup = FunctionTool<Void>(
            name: "lookup",
            description: "Lookup.",
            parameters: ["type": "object"]
        ) { context, _ in
            await sawOutputSchema.append(context.agent?.outputSchema == nil ? "public" : "execution")
            return .text("lookup")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [lookup], model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Lookup",
            outputType: StructuredAnswer.self,
            outputSchema: schema
        )

        #expect(await sawOutputSchema.all() == ["public"])
        let requests = await model.requests()
        #expect(requests.first?.outputSchema?.name == "StructuredAnswer")
    }

    @Test
    func functionToolStrictSchemaNormalizesParametersForModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let tool = FunctionTool<Void>(
            name: "lookup",
            description: "Lookup.",
            parameters: [
                "type": "object",
                "properties": [
                    "customer_id": ["type": "string", "default": nil],
                    "tags": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"]
                            ]
                        ]
                    ]
                ]
            ]
        ) { _, _ in
            .text("unused")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        _ = try await Runner.run(agent: agent, input: "Hi")

        let requests = await model.requests()
        let descriptor = requests.first?.tools.first
        guard case .function(let functionDescriptor) = descriptor else {
            Issue.record("Expected function tool descriptor")
            return
        }
        #expect(functionDescriptor.strict)
        #expect(functionDescriptor.parameters["additionalProperties"] == .bool(false))
        let requiredNames = Set(functionDescriptor.parameters["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        #expect(requiredNames == ["customer_id", "tags"])
        #expect(functionDescriptor.parameters["properties"]?["customer_id"]?["default"] == nil)
        #expect(functionDescriptor.parameters["properties"]?["tags"]?["items"]?["additionalProperties"] == .bool(false))
        #expect(functionDescriptor.parameters["properties"]?["tags"]?["items"]?["required"] == ["name"])
    }
}
