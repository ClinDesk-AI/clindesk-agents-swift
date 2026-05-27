import Testing
import ClinDeskAgents

@Suite
struct HandoffRoutingTests {
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
        #expect(result.lastAgent.name == "Booking")
        #expect(result.lastAgent.handoffDescription == "Books appointments.")
        #expect(Handoff<Void>.defaultToolDescription(for: booking) ==
            "Handoff to the Booking agent to handle the request. Books appointments.")
        let bookingRequests = await bookingModel.requests()
        #expect(bookingRequests.first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_transfer"
                    && output.output.stringValue == #"{"assistant": "Booking"}"#
            }
            return false
        } == true)
        #expect(result.newItems.contains(.functionCallOutput(FunctionCallOutput(
            callID: "call_transfer",
            output: #"{"assistant": "Booking"}"#
        ))))
    }

    @Test
    func multipleHandoffsReturnIgnoredOutputsForExtraCalls() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_booking", name: "transfer_to_booking", arguments: [:])),
                .functionCall(FunctionCall(callID: "call_billing", name: "transfer_to_billing", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Booking wins."))
            ])
        ])
        let billing = Agent<Void>(name: "Billing")
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(to: booking, toolName: "transfer_to_booking"),
                Handoff(to: billing, toolName: "transfer_to_billing")
            ],
            model: triageModel
        )

        let result = try await Runner.run(agent: triage, input: "Need help")

        #expect(result.finalOutput == "Booking wins.")
        #expect(result.lastAgentName == "Booking")
        #expect(result.lastAgent.name == "Booking")
        let bookingRequests = await bookingModel.requests()
        let input = try #require(bookingRequests.first?.input)
        #expect(input.contains(.functionCallOutput(FunctionCallOutput(
            callID: "call_booking",
            output: #"{"assistant": "Booking"}"#
        ))))
        #expect(input.contains(.functionCallOutput(FunctionCallOutput(
            callID: "call_billing",
            output: "Multiple handoffs detected, ignoring this one."
        ))))
    }
}
