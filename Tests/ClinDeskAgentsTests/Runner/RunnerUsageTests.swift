import Testing
import ClinDeskAgents

@Suite
struct RunnerUsageTests {
    @Test
    func accumulatesUsageAcrossModelResponsesAndExposesItToTools() async throws {
        let model = FakeModel([
            ModelResponse(
                output: [
                    .functionCall(FunctionCall(callID: "call_usage", name: "usage_seen", arguments: [:]))
                ],
                usage: Usage(
                    requests: 1,
                    inputTokens: 10,
                    inputTokensDetails: InputTokensDetails(cachedTokens: 4),
                    outputTokens: 3,
                    outputTokensDetails: OutputTokensDetails(reasoningTokens: 1),
                    totalTokens: 13
                ),
                responseID: "resp_1"
            ),
            ModelResponse(
                output: [
                    .message(AgentMessage(role: .assistant, content: "Done."))
                ],
                usage: Usage(
                    requests: 1,
                    inputTokens: 6,
                    inputTokensDetails: InputTokensDetails(cachedTokens: 2),
                    outputTokens: 5,
                    outputTokensDetails: OutputTokensDetails(reasoningTokens: 2),
                    totalTokens: 11
                ),
                responseID: "resp_2"
            )
        ])
        let usageSeen = FunctionTool<Void>(name: "usage_seen", description: "Return visible usage.") { context, _ in
            .text("\(context.runContext.usage.totalTokens)")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [usageSeen], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Done.")
        #expect(result.responseID == "resp_2")
        #expect(result.modelResponses.map(\.responseID) == ["resp_1", "resp_2"])
        #expect(result.usage.requests == 2)
        #expect(result.usage.inputTokens == 16)
        #expect(result.usage.outputTokens == 8)
        #expect(result.usage.totalTokens == 24)
        #expect(result.usage.inputTokensDetails.cachedTokens == 6)
        #expect(result.usage.outputTokensDetails.reasoningTokens == 3)
        #expect(result.usage.requestUsageEntries.map(\.totalTokens) == [13, 11])
        #expect(result.newItems.contains(.functionCallOutput(FunctionCallOutput(
            callID: "call_usage",
            output: .string("13")
        ))))
    }
}
