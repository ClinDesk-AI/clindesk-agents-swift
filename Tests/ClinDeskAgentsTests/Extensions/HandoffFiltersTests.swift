import Testing
import ClinDeskAgents

@Suite
struct HandoffFiltersTests {
    @Test
    func removeAllToolsFiltersToolItemsFromHandoffInputData() async {
        let userMessage = ModelInputItem.message(AgentMessage(role: .user, content: "Need help"))
        let assistantMessage = ModelInputItem.message(AgentMessage(role: .assistant, content: "Keeping this"))
        let handoffData = HandoffInputData<Void>(
            inputHistory: [
                userMessage,
                .functionCall(FunctionCall(callID: "call_history", name: "lookup", arguments: [:])),
                .raw(["type": "shell_call", "name": "shell"])
            ],
            preHandoffItems: [
                assistantMessage,
                .customToolCall(CustomToolCall(callID: "call_custom", name: "raw_editor", input: "draft"))
            ],
            newItems: [
                .functionCall(FunctionCall(callID: "call_handoff", name: "transfer_to_booking", arguments: [:])),
                .reasoning(["summary": "hidden"])
            ],
            inputItems: [
                .raw(["type": "reasoning", "summary": "hidden"]),
                userMessage
            ]
        )

        let filtered = await HandoffFilters.removeAllTools(handoffData)

        #expect(filtered.inputHistory == [userMessage])
        #expect(filtered.preHandoffItems == [assistantMessage])
        #expect(filtered.newItems == [])
        #expect(filtered.inputItems == [userMessage])
    }

    @Test
    func removeAllToolsCanBeUsedAsHandoffInputFilter() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Booking ready."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(
                    to: booking,
                    toolName: "transfer_to_booking",
                    inputFilter: HandoffFilters.removeAllTools
                )
            ],
            model: triageModel
        )

        _ = try await Runner.run(agent: triage, input: "Need an appointment")

        let requests = await bookingModel.requests()
        #expect(requests.first?.input == [
            .message(AgentMessage(role: .user, content: "Need an appointment"))
        ])
    }
}
