import Foundation
import Testing
import ClinDeskAgents
import ClinDeskAgentsOpenAI

@Suite
struct RunnerTests {
    @Test
    func returnsFinalOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Hello from Swift."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Be concise."),
            model: model
        )

        let result = try await Runner.run(agent: agent, input: "Hi")

        #expect(result.finalOutput == "Hello from Swift.")
        #expect(result.lastAgentName == "Assistant")
    }

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

        let agent = Agent<Void>(
            name: "Weather",
            tools: [weather],
            model: model
        )

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
    func stopOnFirstToolReturnsToolOutput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_quote", name: "quote", arguments: [:]))
            ])
        ])
        let quote = FunctionTool<Void>(
            name: "quote",
            description: "Return a quote."
        ) { _, _ in
            .json(["price": "1200 MXN"])
        }
        let agent = Agent<Void>(
            name: "Quoter",
            tools: [quote],
            model: model,
            toolUseBehavior: .stopOnFirstTool
        )

        let result = try await Runner.run(agent: agent, input: "Quote?")

        #expect(result.finalOutput == #"{"price":"1200 MXN"}"#)
    }

    @Test
    func handoffSwitchesAgents() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "I can help book that appointment."))
            ])
        ])
        let booking = Agent<Void>(
            name: "Booking",
            handoffDescription: "Books appointments.",
            model: bookingModel
        )
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        let result = try await Runner.run(agent: triage, input: "Need an appointment")

        #expect(result.finalOutput == "I can help book that appointment.")
        #expect(result.lastAgentName == "Booking")
    }

    @Test
    func inputGuardrailStopsRun() async throws {
        let model = FakeModel([])
        let guardrail = InputGuardrail<Void>(name: "blocked") { _, _, _ in
            GuardrailFunctionOutput(outputInfo: "blocked input", tripwireTriggered: true)
        }
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            inputGuardrails: [guardrail]
        )

        await #expect(throws: AgentsError.inputGuardrailTripwire(name: "blocked", reason: "blocked input")) {
            _ = try await Runner.run(agent: agent, input: "Nope")
        }
    }

    @Test
    func memorySessionStoresTurnItems() async throws {
        let session = MemorySession(id: "thread-1")
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Stored."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: "Remember this",
            runConfig: RunConfig(session: session)
        )

        let items = try await session.getItems()
        #expect(items.count == 2)
    }

    @Test
    func openAIProviderEncodesToolsAndDecodesFunctionCalls() async throws {
        let capture = RequestCapture()
        let response = """
        {
          "id": "resp_123",
          "output": [
            {
              "type": "function_call",
              "id": "fc_123",
              "call_id": "call_123",
              "name": "lookup",
              "arguments": "{\\"query\\":\\"clinic hours\\"}"
            }
          ],
          "usage": {
            "input_tokens": 10,
            "output_tokens": 5,
            "total_tokens": 15
          }
        }
        """.data(using: .utf8)!

        let model = OpenAIResponsesModel(apiKey: "test") { request in
            await capture.set(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, http)
        }

        let tool = ToolDescriptor(
            name: "lookup",
            description: "Look up clinic facts.",
            parameters: ["type": "object"]
        )
        let result = try await model.getResponse(ModelRequest<Void>(
            instructions: "Use tools.",
            input: [.message(AgentMessage(role: .user, content: "hours?"))],
            context: RunContext(),
            settings: ModelSettings(maxOutputTokens: 200),
            tools: [tool],
            handoffs: []
        ))

        #expect(result.id == "resp_123")
        #expect(result.functionCalls.first?.name == "lookup")
        #expect(result.usage?.totalTokens == 15)

        let request = await capture.request
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test")
        let body = try #require(request?.httpBody)
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json["tools"] != nil)
        #expect(json["max_output_tokens"] != nil)
    }
}

private actor FakeModelStore {
    var responses: [ModelResponse]

    init(_ responses: [ModelResponse]) {
        self.responses = responses
    }

    func next() throws -> ModelResponse {
        guard !responses.isEmpty else {
            throw AgentsError.invalidModelResponse("No fake response queued.")
        }
        return responses.removeFirst()
    }
}

private struct FakeModel: Model {
    let store: FakeModelStore

    init(_ responses: [ModelResponse]) {
        self.store = FakeModelStore(responses)
    }

    func getResponse<Context: Sendable>(_ request: ModelRequest<Context>) async throws -> ModelResponse {
        try await store.next()
    }
}

private actor RequestCapture {
    private(set) var request: URLRequest?

    func set(_ request: URLRequest) {
        self.request = request
    }
}
