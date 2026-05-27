import Testing
import ClinDeskAgents

@Suite
struct HandoffCallbackTests {
    @Test
    func handoffOnHandoffCallbackRunsBeforeAgentSwitch() async throws {
        let recorder = StringRecorder()
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Callback complete."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(
                    to: booking,
                    toolName: "transfer_to_booking",
                    onHandoff: { context in
                        await recorder.append("run:\(context.runID)")
                    }
                )
            ],
            model: triageModel
        )

        let result = try await Runner.run(agent: triage, input: "Need help")

        #expect(result.finalOutput == "Callback complete.")
        #expect(await recorder.all().count == 1)
        #expect((await recorder.all()).first?.hasPrefix("run:") == true)
    }

    @Test
    func handoffOnHandoffCallbackReceivesTypedInput() async throws {
        struct BookingRequest: Decodable, Sendable {
            let reason: String
        }

        let recorder = StringRecorder()
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_transfer",
                    name: "transfer_to_booking",
                    arguments: ["reason": "annual checkup"]
                ))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Typed callback complete."))
            ])
        ])
        let inputSchema: JSONValue = [
            "type": "object",
            "properties": [
                "reason": ["type": "string", "default": nil]
            ]
        ]
        let strictInputSchema: JSONValue = [
            "type": "object",
            "properties": [
                "reason": ["type": "string"]
            ],
            "required": ["reason"],
            "additionalProperties": false
        ]
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(
                    to: booking,
                    toolName: "transfer_to_booking",
                    inputSchema: inputSchema,
                    onHandoff: { (_: RunContext<Void>, input: BookingRequest) in
                        await recorder.append(input.reason)
                    }
                )
            ],
            model: triageModel
        )

        let result = try await Runner.run(agent: triage, input: "Need help")

        #expect(result.finalOutput == "Typed callback complete.")
        #expect(await recorder.all() == ["annual checkup"])
        let triageRequests = await triageModel.requests()
        #expect(triageRequests.first?.handoffs.first?.inputSchema == strictInputSchema)
    }

    @Test
    func handoffDefaultInputSchemaIsStrictEmptyObject() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "No handoff."))
            ])
        ])
        let child = Agent<Void>(name: "Child")
        let agent = Agent<Void>(
            name: "Parent",
            handoffs: [Handoff(to: child, toolName: "transfer_to_child")],
            model: model
        )

        _ = try await Runner.run(agent: agent, input: "Hi")

        let requests = await model.requests()
        #expect(requests.first?.handoffs.first?.inputSchema == StrictSchema.emptySchema)
    }

    @Test
    func invalidStrictHandoffSchemaFailsBeforeModelRequest() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "unused"))
            ])
        ])
        let child = Agent<Void>(name: "Child")
        let agent = Agent<Void>(
            name: "Parent",
            handoffs: [
                Handoff(
                    to: child,
                    toolName: "transfer_to_child",
                    inputSchema: [
                        "type": "object",
                        "additionalProperties": true
                    ]
                )
            ],
            model: model
        )

        do {
            _ = try await Runner.run(agent: agent, input: "Hi")
            Issue.record("Expected invalid strict schema")
        } catch AgentsError.invalidRunConfig(let message) {
            #expect(message.contains("Invalid strict JSON schema for handoff 'transfer_to_child'"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await model.requests().isEmpty)
    }
}
