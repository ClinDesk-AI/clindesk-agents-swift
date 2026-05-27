import Testing
import ClinDeskAgents

@Suite
struct HandoffInputFilterTests {
    @Test
    func handoffInputFilterCanRewriteModelInput() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [
                Handoff(
                    to: booking,
                    toolName: "transfer_to_booking",
                    isEnabled: { _ in true },
                    inputFilter: { data in
                        data.clone(
                            inputHistory: [.message(AgentMessage(role: .user, content: "filtered input"))],
                            preHandoffItems: [],
                            newItems: []
                        )
                    }
                )
            ],
            model: triageModel
        )

        _ = try await Runner.run(agent: triage, input: "original")

        let requests = await bookingModel.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "filtered input"))])
    }

    @Test
    func runConfigHandoffInputFilterAppliesWhenHandoffDoesNotOverride() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered by run config."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        _ = try await Runner.run(
            agent: triage,
            input: "original",
            runConfig: RunConfig(handoffInputFilter: { data in
                data.clone(
                    inputHistory: [.message(AgentMessage(role: .user, content: "run config filtered input"))],
                    preHandoffItems: [],
                    newItems: []
                )
            })
        )

        let requests = await bookingModel.requests()
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "run config filtered input"))])
    }
}
