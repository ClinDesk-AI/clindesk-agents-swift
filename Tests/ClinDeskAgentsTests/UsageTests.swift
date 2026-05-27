import Foundation
import Testing
import ClinDeskAgents

@Suite
struct UsageTests {
    @Test
    func decodesSerializedUsageDetailsFromObjectOrArray() throws {
        let objectEncoded = """
        {
          "requests": 1,
          "input_tokens": 10,
          "input_tokens_details": {"cached_tokens": 4},
          "output_tokens": 3,
          "output_tokens_details": {"reasoning_tokens": 1},
          "total_tokens": 13
        }
        """.data(using: .utf8)!

        let arrayEncoded = """
        {
          "requests": 1,
          "input_tokens": 6,
          "input_tokens_details": [{"cached_tokens": 2}],
          "output_tokens": 5,
          "output_tokens_details": [{"reasoning_tokens": 2}],
          "total_tokens": 11
        }
        """.data(using: .utf8)!

        let objectUsage = try JSONDecoder().decode(Usage.self, from: objectEncoded)
        let arrayUsage = try JSONDecoder().decode(Usage.self, from: arrayEncoded)

        #expect(objectUsage.inputTokensDetails.cachedTokens == 4)
        #expect(objectUsage.outputTokensDetails.reasoningTokens == 1)
        #expect(arrayUsage.inputTokensDetails.cachedTokens == 2)
        #expect(arrayUsage.outputTokensDetails.reasoningTokens == 2)
    }

    @Test
    func encodesUsageUsingUpstreamSerializedShape() throws {
        let usage = Usage(
            requests: 1,
            inputTokens: 10,
            inputTokensDetails: InputTokensDetails(cachedTokens: 4),
            outputTokens: 3,
            outputTokensDetails: OutputTokensDetails(reasoningTokens: 1),
            totalTokens: 13
        )

        let encoded = try JSONEncoder().encode(usage)
        let json = try JSONDecoder().decode(JSONValue.self, from: encoded)

        #expect(json["input_tokens_details"]?.arrayValue?.first?["cached_tokens"] == 4)
        #expect(json["output_tokens_details"]?.arrayValue?.first?["reasoning_tokens"] == 1)
    }

    @Test
    func usageSpanSerializersMirrorUpstreamShapes() {
        let usage = Usage(
            requests: 2,
            inputTokens: 10,
            inputTokensDetails: InputTokensDetails(cachedTokens: 4),
            outputTokens: 3,
            outputTokensDetails: OutputTokensDetails(reasoningTokens: 1),
            totalTokens: 13
        )

        #expect(usage.modelSpanUsage == [
            "requests": 2,
            "input_tokens": 10,
            "output_tokens": 3,
            "total_tokens": 13,
            "input_tokens_details": ["cached_tokens": 4],
            "output_tokens_details": ["reasoning_tokens": 1]
        ])
        #expect(usage.totalSpanMetadata == [
            "requests": 2,
            "input_tokens": 10,
            "output_tokens": 3,
            "total_tokens": 13,
            "cached_input_tokens": 4
        ])
        #expect(usage.turnSpanUsage == [
            "input_tokens": 10,
            "output_tokens": 3,
            "cached_input_tokens": 4
        ])
        #expect(usage.taskSpanUsage == [
            "input_tokens": 10,
            "output_tokens": 3,
            "cached_input_tokens": 4,
            "requests": 2,
            "total_tokens": 13
        ])
    }
}
