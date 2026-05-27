import Foundation

public struct InputTokensDetails: Codable, Equatable, Sendable {
    public var cachedTokens: Int

    public init(cachedTokens: Int = 0) {
        self.cachedTokens = cachedTokens
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

public struct OutputTokensDetails: Codable, Equatable, Sendable {
    public var reasoningTokens: Int

    public init(reasoningTokens: Int = 0) {
        self.reasoningTokens = reasoningTokens
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }
}

public struct RequestUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var inputTokensDetails: InputTokensDetails
    public var outputTokensDetails: OutputTokensDetails

    public init(
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        inputTokensDetails: InputTokensDetails = InputTokensDetails(),
        outputTokensDetails: OutputTokensDetails = OutputTokensDetails()
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputTokensDetails = inputTokensDetails
        self.outputTokensDetails = outputTokensDetails
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
    }
}

public struct Usage: Codable, Equatable, Sendable {
    public var requests: Int
    public var inputTokens: Int
    public var inputTokensDetails: InputTokensDetails
    public var outputTokens: Int
    public var outputTokensDetails: OutputTokensDetails
    public var totalTokens: Int
    public var requestUsageEntries: [RequestUsage]

    public init(
        requests: Int = 0,
        inputTokens: Int = 0,
        inputTokensDetails: InputTokensDetails = InputTokensDetails(),
        outputTokens: Int = 0,
        outputTokensDetails: OutputTokensDetails = OutputTokensDetails(),
        totalTokens: Int = 0,
        requestUsageEntries: [RequestUsage] = []
    ) {
        self.requests = requests
        self.inputTokens = inputTokens
        self.inputTokensDetails = inputTokensDetails
        self.outputTokens = outputTokens
        self.outputTokensDetails = outputTokensDetails
        self.totalTokens = totalTokens
        self.requestUsageEntries = requestUsageEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requests = try container.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.inputTokensDetails = try container.decodeInputTokensDetails(forKey: .inputTokensDetails)
        self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.outputTokensDetails = try container.decodeOutputTokensDetails(forKey: .outputTokensDetails)
        self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        self.requestUsageEntries = try container.decodeIfPresent(
            [RequestUsage].self,
            forKey: .requestUsageEntries
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requests, forKey: .requests)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode([inputTokensDetails], forKey: .inputTokensDetails)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode([outputTokensDetails], forKey: .outputTokensDetails)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(requestUsageEntries, forKey: .requestUsageEntries)
    }

    public mutating func add(_ other: Usage) {
        requests += other.requests
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
        inputTokensDetails.cachedTokens += other.inputTokensDetails.cachedTokens
        outputTokensDetails.reasoningTokens += other.outputTokensDetails.reasoningTokens

        if !other.requestUsageEntries.isEmpty {
            requestUsageEntries.append(contentsOf: other.requestUsageEntries)
        } else if other.requests == 1 && other.totalTokens > 0 {
            requestUsageEntries.append(RequestUsage(
                inputTokens: other.inputTokens,
                outputTokens: other.outputTokens,
                totalTokens: other.totalTokens,
                inputTokensDetails: other.inputTokensDetails,
                outputTokensDetails: other.outputTokensDetails
            ))
        }
    }

    public static func + (lhs: Usage, rhs: Usage) -> Usage {
        var usage = lhs
        usage.add(rhs)
        return usage
    }

    public var spanMetadata: [String: Int] {
        [
            "requests": requests,
            "input_tokens": inputTokens,
            "output_tokens": outputTokens,
            "total_tokens": totalTokens,
            "cached_input_tokens": inputTokensDetails.cachedTokens
        ]
    }

    public var modelSpanUsage: [String: JSONValue] {
        [
            "requests": .number(Double(requests)),
            "input_tokens": .number(Double(inputTokens)),
            "output_tokens": .number(Double(outputTokens)),
            "total_tokens": .number(Double(totalTokens)),
            "input_tokens_details": .object([
                "cached_tokens": .number(Double(inputTokensDetails.cachedTokens))
            ]),
            "output_tokens_details": .object([
                "reasoning_tokens": .number(Double(outputTokensDetails.reasoningTokens))
            ])
        ]
    }

    public var totalSpanMetadata: [String: JSONValue] {
        [
            "requests": .number(Double(requests)),
            "input_tokens": .number(Double(inputTokens)),
            "output_tokens": .number(Double(outputTokens)),
            "total_tokens": .number(Double(totalTokens)),
            "cached_input_tokens": .number(Double(inputTokensDetails.cachedTokens))
        ]
    }

    public var turnSpanUsage: [String: JSONValue] {
        [
            "input_tokens": .number(Double(inputTokens)),
            "output_tokens": .number(Double(outputTokens)),
            "cached_input_tokens": .number(Double(inputTokensDetails.cachedTokens))
        ]
    }

    public var taskSpanUsage: [String: JSONValue] {
        var usage = turnSpanUsage
        usage["requests"] = .number(Double(requests))
        usage["total_tokens"] = .number(Double(totalTokens))
        return usage
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case requests
        case inputTokens = "input_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokens = "output_tokens"
        case outputTokensDetails = "output_tokens_details"
        case totalTokens = "total_tokens"
        case requestUsageEntries = "request_usage_entries"
    }
}

private extension KeyedDecodingContainer where K == Usage.CodingKeys {
    func decodeInputTokensDetails(forKey key: K) throws -> InputTokensDetails {
        if let details = try? decode(InputTokensDetails.self, forKey: key) {
            return details
        }
        if let details = try? decode([InputTokensDetails].self, forKey: key),
           let first = details.first
        {
            return first
        }
        return InputTokensDetails()
    }

    func decodeOutputTokensDetails(forKey key: K) throws -> OutputTokensDetails {
        if let details = try? decode(OutputTokensDetails.self, forKey: key) {
            return details
        }
        if let details = try? decode([OutputTokensDetails].self, forKey: key),
           let first = details.first
        {
            return first
        }
        return OutputTokensDetails()
    }
}
