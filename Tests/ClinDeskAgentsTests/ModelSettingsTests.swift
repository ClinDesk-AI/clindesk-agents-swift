import Testing
import Foundation
import ClinDeskAgents

@Suite
struct ModelSettingsTests {
    @Test
    func modelSettingsResolveOverlaysNonNilValuesAndMergesExtraArgs() {
        let base = ModelSettings(
            temperature: 0.1,
            topP: 0.8,
            metadata: ["base": "yes"],
            store: true,
            promptCacheRetention: .inMemory,
            responseInclude: ["message.output_text.logprobs"],
            contextManagement: [
                [
                    "type": "local_compaction",
                    "threshold": 512
                ]
            ],
            extraArgs: [
                "base": .bool(true),
                "shared": .string("base")
            ],
            retry: ModelRetrySettings(
                maxRetries: 1,
                backoff: ModelRetryBackoffSettings(initialDelay: 0.1, maxDelay: 1)
            )
        )
        let override = ModelSettings(
            topP: 0.9,
            metadata: [:],
            promptCacheRetention: .twentyFourHours,
            responseInclude: [],
            extraArgs: [
                "shared": .string("override"),
                "override": .number(1)
            ],
            retry: ModelRetrySettings(
                maxRetries: 3,
                backoff: ModelRetryBackoffSettings(multiplier: 3, jitter: false)
            )
        )

        let resolved = base.resolve(override)

        #expect(resolved.temperature == 0.1)
        #expect(resolved.topP == 0.9)
        #expect(resolved.metadata == [:])
        #expect(resolved.store == true)
        #expect(resolved.promptCacheRetention == .twentyFourHours)
        #expect(resolved.responseInclude == [])
        #expect(resolved.contextManagement == [
            [
                "type": .string("local_compaction"),
                "threshold": .number(512)
            ]
        ])
        #expect(resolved.retry?.maxRetries == 3)
        #expect(resolved.retry?.backoff == ModelRetryBackoffSettings(
            initialDelay: 0.1,
            maxDelay: 1,
            multiplier: 3,
            jitter: false
        ))
        let expectedExtraArgs: [String: JSONValue] = [
            "base": .bool(true),
            "shared": .string("override"),
            "override": .number(1)
        ]
        #expect(resolved.extraArgs == expectedExtraArgs)
    }

    @Test
    func modelSettingsToJSONDictionaryUsesUpstreamSnakeCaseShape() {
        let settings = ModelSettings(
            temperature: 0.2,
            topP: 0.8,
            frequencyPenalty: 0.1,
            presencePenalty: 0.3,
            toolChoice: .named("lookup"),
            parallelToolCalls: false,
            truncation: .auto,
            maxTokens: 42,
            reasoning: ["effort": "medium"],
            verbosity: .high,
            metadata: ["workflow": "booking"],
            store: false,
            promptCacheRetention: .twentyFourHours,
            includeUsage: true,
            responseInclude: ["message.output_text.logprobs", "reasoning.encrypted_content"],
            topLogprobs: 3,
            contextManagement: [
                [
                    "type": "local_compaction",
                    "compact_threshold": 200000
                ]
            ],
            extraArgs: ["custom_arg": .number(7)],
            retry: ModelRetrySettings(
                maxRetries: 2,
                backoff: ModelRetryBackoffSettings(initialDelay: 0.5, jitter: true),
                policy: RetryPolicies.never()
            )
        )

        let json = settings.toJSONDictionary()

        #expect(json["temperature"] == .number(0.2))
        #expect(json["top_p"] == .number(0.8))
        #expect(json["frequency_penalty"] == .number(0.1))
        #expect(json["presence_penalty"] == .number(0.3))
        #expect(json["tool_choice"] == .string("lookup"))
        #expect(json["parallel_tool_calls"] == .bool(false))
        #expect(json["truncation"] == .string("auto"))
        #expect(json["max_tokens"] == .number(42))
        #expect(json["reasoning"] == ["effort": .string("medium")])
        #expect(json["verbosity"] == .string("high"))
        #expect(json["metadata"] == ["workflow": .string("booking")])
        #expect(json["store"] == .bool(false))
        #expect(json["prompt_cache_retention"] == .string("24h"))
        #expect(json["include_usage"] == .bool(true))
        #expect(json["response_include"] == [
            .string("message.output_text.logprobs"),
            .string("reasoning.encrypted_content")
        ])
        #expect(json["top_logprobs"] == .number(3))
        #expect(json["context_management"] == [
            [
                "type": .string("local_compaction"),
                "compact_threshold": .number(200000)
            ]
        ])
        #expect(json["extra_args"] == ["custom_arg": .number(7)])
        #expect(json["retry"]?["max_retries"] == .number(2))
        #expect(json["retry"]?["backoff"]?["initial_delay"] == .number(0.5))
        #expect(json["retry"]?["backoff"]?["max_delay"] == .null)
        #expect(json["retry"]?["backoff"]?["jitter"] == .bool(true))
        #expect(json["retry"]?["policy"] == nil)
        #expect(json["topP"] == nil)
        #expect(ModelSettings().toJSONDictionary()["temperature"] == .null)
    }

    @Test
    func modelSettingsCodableUsesUpstreamSnakeCaseShape() throws {
        let settings = ModelSettings(
            topP: 0.7,
            frequencyPenalty: 0.2,
            presencePenalty: 0.4,
            toolChoice: .required,
            parallelToolCalls: true,
            maxTokens: 128,
            promptCacheRetention: .inMemory,
            includeUsage: false,
            responseInclude: ["message.output_text.logprobs"],
            topLogprobs: 2,
            contextManagement: [["type": "local_compaction"]],
            extraArgs: ["local_hint": .string("fast")]
        )

        let data = try JSONEncoder().encode(settings)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)

        #expect(json["top_p"] == .number(0.7))
        #expect(json["frequency_penalty"] == .number(0.2))
        #expect(json["presence_penalty"] == .number(0.4))
        #expect(json["tool_choice"] == .string("required"))
        #expect(json["parallel_tool_calls"] == .bool(true))
        #expect(json["max_tokens"] == .number(128))
        #expect(json["prompt_cache_retention"] == .string("in_memory"))
        #expect(json["include_usage"] == .bool(false))
        #expect(json["response_include"] == [.string("message.output_text.logprobs")])
        #expect(json["top_logprobs"] == .number(2))
        #expect(json["context_management"] == [["type": .string("local_compaction")]])
        #expect(json["extra_args"] == ["local_hint": .string("fast")])
        #expect(json["topP"] == nil)
        #expect(json["frequencyPenalty"] == nil)
        #expect(try JSONDecoder().decode(ModelSettings.self, from: data) == settings)
    }

    @Test
    func modelSettingsToTraceableDictionaryOmitsProviderSpecificExtras() {
        let settings = ModelSettings(
            temperature: 0.4,
            store: true,
            promptCacheRetention: .inMemory,
            responseInclude: ["message.output_text.logprobs"],
            contextManagement: [["type": "local_compaction"]],
            extraArgs: ["custom": .string("value")],
            retry: ModelRetrySettings(maxRetries: 1)
        )

        let traceable = settings.toTraceableDictionary()

        #expect(traceable["temperature"] == .number(0.4))
        #expect(traceable["store"] == .bool(true))
        #expect(traceable["prompt_cache_retention"] == .string("in_memory"))
        #expect(traceable["response_include"] == [.string("message.output_text.logprobs")])
        #expect(traceable["context_management"] == [["type": .string("local_compaction")]])
        #expect(traceable["retry"]?["max_retries"] == .number(1))
        #expect(traceable["top_p"] == .null)
        #expect(traceable["extra_args"] == nil)
    }
}
