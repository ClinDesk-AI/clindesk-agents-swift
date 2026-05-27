import Foundation

public enum ToolChoice: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    case auto
    case required
    case none
    case named(String)

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(_ value: String) {
        switch value {
        case "auto":
            self = .auto
        case "required":
            self = .required
        case "none":
            self = .none
        default:
            self = .named(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self.init(string)
            return
        }
        throw DecodingError.typeMismatch(
            ToolChoice.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "ToolChoice must be a string in the local-only runtime."
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .required:
            try container.encode("required")
        case .none:
            try container.encode("none")
        case .named(let name):
            try container.encode(name)
        }
    }
}

public enum ModelTruncation: String, Codable, Equatable, Sendable {
    case auto
    case disabled
}

public enum ModelVerbosity: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum PromptCacheRetention: String, Codable, Equatable, Sendable {
    case inMemory = "in_memory"
    case twentyFourHours = "24h"
}

public struct ModelSettings: Codable, Equatable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var toolChoice: ToolChoice?
    public var parallelToolCalls: Bool?
    public var truncation: ModelTruncation?
    public var maxTokens: Int?
    public var reasoning: JSONValue?
    public var verbosity: ModelVerbosity?
    public var metadata: [String: String]?
    public var store: Bool?
    public var promptCacheRetention: PromptCacheRetention?
    public var includeUsage: Bool?
    public var responseInclude: [String]?
    public var topLogprobs: Int?
    public var contextManagement: [JSONValue]?
    public var extraArgs: [String: JSONValue]?
    public var retry: ModelRetrySettings?

    public var maxOutputTokens: Int? {
        get { maxTokens }
        set { maxTokens = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case truncation
        case maxTokens = "max_tokens"
        case reasoning
        case verbosity
        case metadata
        case store
        case promptCacheRetention = "prompt_cache_retention"
        case includeUsage = "include_usage"
        case responseInclude = "response_include"
        case topLogprobs = "top_logprobs"
        case contextManagement = "context_management"
        case extraArgs = "extra_args"
        case retry
    }

    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        toolChoice: ToolChoice? = nil,
        parallelToolCalls: Bool? = nil,
        truncation: ModelTruncation? = nil,
        maxTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        reasoning: JSONValue? = nil,
        verbosity: ModelVerbosity? = nil,
        metadata: [String: String]? = nil,
        store: Bool? = nil,
        promptCacheRetention: PromptCacheRetention? = nil,
        includeUsage: Bool? = nil,
        responseInclude: [String]? = nil,
        topLogprobs: Int? = nil,
        contextManagement: [JSONValue]? = nil,
        extraArgs: [String: JSONValue]? = nil,
        retry: ModelRetrySettings? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.truncation = truncation
        self.maxTokens = maxTokens ?? maxOutputTokens
        self.reasoning = reasoning
        self.verbosity = verbosity
        self.metadata = metadata
        self.store = store
        self.promptCacheRetention = promptCacheRetention
        self.includeUsage = includeUsage
        self.responseInclude = responseInclude
        self.topLogprobs = topLogprobs
        self.contextManagement = contextManagement
        self.extraArgs = extraArgs
        self.retry = retry
    }

    public func resolve(_ override: ModelSettings?) -> ModelSettings {
        guard let override else {
            return self
        }
        return ModelSettings(
            temperature: override.temperature ?? temperature,
            topP: override.topP ?? topP,
            frequencyPenalty: override.frequencyPenalty ?? frequencyPenalty,
            presencePenalty: override.presencePenalty ?? presencePenalty,
            toolChoice: override.toolChoice ?? toolChoice,
            parallelToolCalls: override.parallelToolCalls ?? parallelToolCalls,
            truncation: override.truncation ?? truncation,
            maxTokens: override.maxTokens ?? maxTokens,
            reasoning: override.reasoning ?? reasoning,
            verbosity: override.verbosity ?? verbosity,
            metadata: override.metadata ?? metadata,
            store: override.store ?? store,
            promptCacheRetention: override.promptCacheRetention ?? promptCacheRetention,
            includeUsage: override.includeUsage ?? includeUsage,
            responseInclude: override.responseInclude ?? responseInclude,
            topLogprobs: override.topLogprobs ?? topLogprobs,
            contextManagement: override.contextManagement ?? contextManagement,
            extraArgs: mergedExtraArgs(with: override),
            retry: mergedRetry(with: override)
        )
    }

    public func merging(_ override: ModelSettings?) -> ModelSettings {
        resolve(override)
    }

    public func toJSONDictionary() -> [String: JSONValue] {
        [
            "temperature": temperature.map { .number($0) } ?? .null,
            "top_p": topP.map { .number($0) } ?? .null,
            "frequency_penalty": frequencyPenalty.map { .number($0) } ?? .null,
            "presence_penalty": presencePenalty.map { .number($0) } ?? .null,
            "tool_choice": toolChoice.map(\.jsonValue) ?? .null,
            "parallel_tool_calls": parallelToolCalls.map { .bool($0) } ?? .null,
            "truncation": truncation.map { .string($0.rawValue) } ?? .null,
            "max_tokens": maxTokens.map { .number(Double($0)) } ?? .null,
            "reasoning": reasoning ?? .null,
            "verbosity": verbosity.map { .string($0.rawValue) } ?? .null,
            "metadata": metadata.map { .object($0.mapValues(JSONValue.string)) } ?? .null,
            "store": store.map { .bool($0) } ?? .null,
            "prompt_cache_retention": promptCacheRetention.map { .string($0.rawValue) } ?? .null,
            "include_usage": includeUsage.map { .bool($0) } ?? .null,
            "response_include": responseInclude.map { .array($0.map(JSONValue.string)) } ?? .null,
            "top_logprobs": topLogprobs.map { .number(Double($0)) } ?? .null,
            "context_management": contextManagement.map { .array($0) } ?? .null,
            "extra_args": extraArgs.map { .object($0) } ?? .null,
            "retry": retry.map { .object($0.toJSONDictionary()) } ?? .null
        ]
    }

    public func toTraceableDictionary() -> [String: JSONValue] {
        let payload = toJSONDictionary()
        return Dictionary(uniqueKeysWithValues: Self.traceableFieldNames.compactMap { key in
            payload[key].map { (key, $0) }
        })
    }

    private func mergedExtraArgs(with override: ModelSettings) -> [String: JSONValue]? {
        guard extraArgs != nil || override.extraArgs != nil else {
            return nil
        }
        var merged = extraArgs ?? [:]
        if let overrideExtraArgs = override.extraArgs {
            merged.merge(overrideExtraArgs) { _, new in new }
        }
        return merged.isEmpty ? nil : merged
    }

    private func mergedRetry(with override: ModelSettings) -> ModelRetrySettings? {
        guard retry != nil || override.retry != nil else {
            return nil
        }
        return retry?.resolve(override.retry) ?? override.retry
    }

    private static let traceableFieldNames: [String] = [
        "temperature",
        "top_p",
        "frequency_penalty",
        "presence_penalty",
        "tool_choice",
        "parallel_tool_calls",
        "truncation",
        "max_tokens",
        "reasoning",
        "verbosity",
        "metadata",
        "store",
        "prompt_cache_retention",
        "include_usage",
        "response_include",
        "top_logprobs",
        "context_management",
        "retry"
    ]
}

public extension ToolChoice {
    var jsonValue: JSONValue {
        switch self {
        case .auto:
            return .string("auto")
        case .required:
            return .string("required")
        case .none:
            return .string("none")
        case .named(let name):
            return .string(name)
        }
    }
}
