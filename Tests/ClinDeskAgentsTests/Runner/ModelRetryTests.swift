import Foundation
import Testing
import ClinDeskAgents

@Suite
struct ModelRetryTests {
    @Test
    func modelRetrySettingsRetryProviderSuggestedFailures() async throws {
        let model = FlakyModel(
            failures: 1,
            error: ProviderHTTPError(statusCode: 429, body: "rate limited"),
            response: ModelResponse(
                output: [
                    .message(AgentMessage(role: .assistant, content: "Retried."))
                ],
                usage: Usage(requests: 1, inputTokens: 2, outputTokens: 3, totalTokens: 5)
            ),
            advice: ModelRetryAdvice(suggested: true, retryAfter: 0, replaySafety: .safe)
        )
        let agent = Agent<Void>(
            name: "Assistant",
            model: model,
            modelSettings: ModelSettings(
                retry: ModelRetrySettings(maxRetries: 1, policy: RetryPolicies.providerSuggested())
            )
        )

        let result = try await Runner.run(agent: agent, input: "Hi")

        #expect(result.finalOutput == "Retried.")
        #expect(result.usage.requests == 2)
        #expect(result.usage.requestUsageEntries.map(\.totalTokens) == [0, 5])
        let requests = await model.requests()
        #expect(requests.count == 2)
    }

}
