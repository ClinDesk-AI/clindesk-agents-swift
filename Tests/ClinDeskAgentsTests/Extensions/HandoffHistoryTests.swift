import Testing
import ClinDeskAgents

@Suite
struct HandoffHistoryTests {
    @Test
    func nestHandoffHistorySummarizesTranscriptAndFiltersSummaryOnlyItems() async throws {
        let userMessage = ModelInputItem.message(AgentMessage(role: .user, content: "Need help"))
        let assistantMessage = ModelInputItem.message(AgentMessage(role: .assistant, content: "I will transfer you."))
        let finalMessage = ModelInputItem.message(AgentMessage(role: .assistant, content: "Booking ready."))
        let handoffData = HandoffInputData<Void>(
            inputHistory: [userMessage],
            preHandoffItems: [
                assistantMessage,
                .functionCallOutput(FunctionCallOutput(callID: "call_lookup", output: "ok"))
            ],
            newItems: [
                .functionCall(FunctionCall(callID: "call_transfer", name: "transfer_to_booking", arguments: [:])),
                finalMessage
            ]
        )

        let nested = try await HandoffHistory.nestHandoffHistory(handoffData)

        let summary = try #require(nested.inputHistory.first)
        guard case .message(let summaryMessage) = summary else {
            Issue.record("Expected nested history to produce an assistant message")
            return
        }
        #expect(summaryMessage.role == .assistant)
        #expect(summaryMessage.content.contains(HandoffHistory.defaultConversationHistoryStart))
        #expect(summaryMessage.content.contains("user: Need help"))
        #expect(summaryMessage.content.contains("function_call"))
        #expect(nested.preHandoffItems == [])
        #expect(nested.inputItems == [finalMessage])
        #expect(nested.newItems == handoffData.newItems)
    }

    @Test
    func runConfigNestHandoffHistoryCollapsesNextAgentInput() async throws {
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
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        _ = try await Runner.run(
            agent: triage,
            input: "Need an appointment",
            runConfig: RunConfig(nestHandoffHistory: true)
        )

        let requests = await bookingModel.requests()
        let input = try #require(requests.first?.input)
        #expect(input.count == 1)
        guard case .message(let summaryMessage) = input.first else {
            Issue.record("Expected next agent to receive nested history")
            return
        }
        #expect(summaryMessage.role == .assistant)
        #expect(summaryMessage.content.contains("user: Need an appointment"))
        #expect(summaryMessage.content.contains("function_call"))
    }

    @Test
    func handoffNestHandoffHistoryOverrideCanDisableRunConfigDefault() async throws {
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
                    nestHandoffHistory: false
                )
            ],
            model: triageModel
        )

        _ = try await Runner.run(
            agent: triage,
            input: "Need an appointment",
            runConfig: RunConfig(nestHandoffHistory: true)
        )

        let requests = await bookingModel.requests()
        #expect(requests.first?.input.contains {
            if case .functionCall(let call) = $0 {
                return call.callID == "call_transfer"
            }
            return false
        } == true)
    }

    @Test
    func handoffHistoryMapperCustomizesNestedHistory() async throws {
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
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        _ = try await Runner.run(
            agent: triage,
            input: "Need an appointment",
            runConfig: RunConfig(
                nestHandoffHistory: true,
                handoffHistoryMapper: { transcript in
                    #expect(!transcript.isEmpty)
                    return [.message(AgentMessage(role: .system, content: "custom history"))]
                }
            )
        )

        let requests = await bookingModel.requests()
        #expect(requests.first?.input.first == .message(AgentMessage(role: .system, content: "custom history")))
    }

    @Test
    func handoffHistoryOmitsProviderDataFromSummariesAndNestedReplay() async throws {
        let rawItem = ModelInputItem.raw([
            "type": "function_call",
            "call_id": "call_lookup",
            "name": "lookup",
            "provider_data": ["trace": "secret"]
        ])
        let handoffData = HandoffInputData<Void>(
            inputHistory: [rawItem],
            preHandoffItems: [],
            newItems: []
        )

        let nested = try await HandoffHistory.nestHandoffHistory(handoffData)
        let summary = try #require(nested.inputHistory.first)
        guard case .message(let summaryMessage) = summary else {
            Issue.record("Expected nested history to produce an assistant message")
            return
        }
        #expect(!summaryMessage.content.contains("provider_data"))
        #expect(summaryMessage.content.contains("function_call"))

        let replaySummary = ModelInputItem.message(AgentMessage(
            role: .assistant,
            content: [
                "For context, here is the conversation so far between the user and the previous agent:",
                HandoffHistory.defaultConversationHistoryStart,
                #"1. {"provider_data":{"trace":"secret"},"role":"user","content":"hello"}"#,
                HandoffHistory.defaultConversationHistoryEnd
            ].joined(separator: "\n")
        ))
        let replay = try await HandoffHistory.nestHandoffHistory(
            HandoffInputData<Void>(
                inputHistory: [replaySummary],
                preHandoffItems: [],
                newItems: []
            )
        )
        let replayOutput = try #require(replay.inputHistory.first)
        guard case .message(let replayMessage) = replayOutput else {
            Issue.record("Expected nested replay to produce an assistant message")
            return
        }
        #expect(!replayMessage.content.contains("provider_data"))
        #expect(replayMessage.content.contains("user: hello"))
    }
}
