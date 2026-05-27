import Testing
import ClinDeskAgents

@Suite
struct CustomToolTests {
    @Test
    func runsCustomToolAndFeedsRawOutputBackToModel() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "hello"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Edited."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            format: ["type": "text"],
            deferLoading: true
        ) { context, input in
            #expect(context.call.callID == "call_custom")
            #expect(context.toolName == "raw_editor")
            #expect(context.toolCallID == "call_custom")
            #expect(context.toolInput == "hello")
            #expect(context.agent?.name == "Assistant")
            #expect(context.runConfig?.modelSettings?.maxOutputTokens == 21)
            return input.uppercased()
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig<Void>(modelSettings: ModelSettings(maxOutputTokens: 21))
        )

        let requests = await model.requests()
        #expect(requests.first?.tools == [
            .custom(CustomToolDescriptor(
                name: "raw_editor",
                description: "Edit raw text.",
                format: ["type": "text"],
                deferLoading: true
            ))
        ])
        #expect(result.finalOutput == "Edited.")
        #expect(result.newItems.contains {
            $0 == .customToolCallOutput(CustomToolCallOutput(
                callID: "call_custom",
                output: "HELLO"
            ))
        })
    }

    @Test
    func typedRunCustomToolContextUsesPublicAgent() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "hello"
                ))
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
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text.",
            format: ["type": "text"],
            deferLoading: true
        ) { context, input in
            await sawOutputSchema.append(context.agent?.outputSchema == nil ? "public" : "execution")
            return input.uppercased()
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Run",
            outputType: StructuredAnswer.self,
            outputSchema: schema
        )

        #expect(await sawOutputSchema.all() == ["public"])
        let requests = await model.requests()
        #expect(requests.first?.outputSchema?.name == "StructuredAnswer")
    }
}
