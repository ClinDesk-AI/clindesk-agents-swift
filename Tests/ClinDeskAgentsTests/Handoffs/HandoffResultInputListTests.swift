import Testing
import ClinDeskAgents

@Suite
struct HandoffResultInputListTests {
    @Test
    func normalizedToInputListUsesFilteredContinuationAfterNestedHandoff() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "triage summary")),
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:]))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "resolution"))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        let result = try await Runner.run(
            agent: triage,
            input: "Need an appointment",
            runConfig: RunConfig(nestHandoffHistory: true)
        )

        let preserveAllInput = result.toInputList()
        let normalizedInput = result.toInputList(mode: .normalized)

        #expect(preserveAllInput.count == 5)
        #expect(normalizedInput.count == 3)
        #expect(preserveAllInput.contains {
            if case .functionCall(let call) = $0 {
                return call.callID == "call_transfer"
            }
            return false
        })
        #expect(preserveAllInput.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_transfer"
            }
            return false
        })
        #expect(!normalizedInput.contains {
            if case .functionCall = $0 {
                return true
            }
            return false
        })
        #expect(!normalizedInput.contains {
            if case .functionCallOutput = $0 {
                return true
            }
            return false
        })
        #expect(normalizedInput.contains(.message(AgentMessage(role: .assistant, content: "triage summary"))))
        #expect(normalizedInput.last == .message(AgentMessage(role: .assistant, content: "resolution")))
    }
}
