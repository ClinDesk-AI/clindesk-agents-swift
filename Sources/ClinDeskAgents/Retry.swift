import Foundation

public struct ModelRetryBackoffSettings: Codable, Equatable, Sendable {
    public var initialDelay: TimeInterval?
    public var maxDelay: TimeInterval?
    public var multiplier: Double?
    public var jitter: Bool?

    public init(
        initialDelay: TimeInterval? = nil,
        maxDelay: TimeInterval? = nil,
        multiplier: Double? = nil,
        jitter: Bool? = nil
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.jitter = jitter
    }

    private enum CodingKeys: String, CodingKey {
        case initialDelay = "initial_delay"
        case maxDelay = "max_delay"
        case multiplier
        case jitter
    }

    public func resolve(_ override: ModelRetryBackoffSettings?) -> ModelRetryBackoffSettings {
        guard let override else {
            return self
        }
        return ModelRetryBackoffSettings(
            initialDelay: override.initialDelay ?? initialDelay,
            maxDelay: override.maxDelay ?? maxDelay,
            multiplier: override.multiplier ?? multiplier,
            jitter: override.jitter ?? jitter
        )
    }

    public func merging(_ override: ModelRetryBackoffSettings?) -> ModelRetryBackoffSettings {
        resolve(override)
    }

    public func toJSONDictionary() -> [String: JSONValue] {
        [
            "initial_delay": initialDelay.map { .number($0) } ?? .null,
            "max_delay": maxDelay.map { .number($0) } ?? .null,
            "multiplier": multiplier.map { .number($0) } ?? .null,
            "jitter": jitter.map { .bool($0) } ?? .null
        ]
    }
}

public enum ModelRetryReplaySafety: String, Codable, Equatable, Sendable {
    case safe
    case unsafe
}

public struct ModelRetryNormalizedError: Equatable, Sendable {
    public var statusCode: Int?
    public var errorCode: String?
    public var message: String?
    public var requestID: String?
    public var retryAfter: TimeInterval?
    public var isAbort: Bool
    public var isNetworkError: Bool
    public var isTimeout: Bool

    public init(
        statusCode: Int? = nil,
        errorCode: String? = nil,
        message: String? = nil,
        requestID: String? = nil,
        retryAfter: TimeInterval? = nil,
        isAbort: Bool = false,
        isNetworkError: Bool = false,
        isTimeout: Bool = false
    ) {
        self.statusCode = statusCode
        self.errorCode = errorCode
        self.message = message
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.isAbort = isAbort
        self.isNetworkError = isNetworkError
        self.isTimeout = isTimeout
    }
}

public struct ModelRetryAdvice: Equatable, Sendable {
    public var suggested: Bool?
    public var retryAfter: TimeInterval?
    public var replaySafety: ModelRetryReplaySafety?
    public var reason: String?
    public var normalized: ModelRetryNormalizedError?

    public init(
        suggested: Bool? = nil,
        retryAfter: TimeInterval? = nil,
        replaySafety: ModelRetryReplaySafety? = nil,
        reason: String? = nil,
        normalized: ModelRetryNormalizedError? = nil
    ) {
        self.suggested = suggested
        self.retryAfter = retryAfter
        self.replaySafety = replaySafety
        self.reason = reason
        self.normalized = normalized
    }
}

public struct ModelRetryAdviceRequest: Sendable {
    public var error: any Error
    public var attempt: Int
    public var stream: Bool

    public init(
        error: any Error,
        attempt: Int,
        stream: Bool
    ) {
        self.error = error
        self.attempt = attempt
        self.stream = stream
    }
}

public struct RetryDecision: Equatable, Sendable {
    public var retry: Bool
    public var delay: TimeInterval?
    public var reason: String?
    var hardVeto: Bool
    var approvesReplay: Bool

    public init(retry: Bool, delay: TimeInterval? = nil, reason: String? = nil) {
        self.retry = retry
        self.delay = delay
        self.reason = reason
        self.hardVeto = false
        self.approvesReplay = false
    }

    public static func replaySafe(_ decision: RetryDecision) -> RetryDecision {
        var decision = decision
        decision.approvesReplay = true
        return decision
    }

    public static func hardVeto(_ decision: RetryDecision) -> RetryDecision {
        var decision = decision
        decision.hardVeto = true
        return decision
    }
}

public struct RetryPolicyContext: Sendable {
    public var error: any Error
    public var attempt: Int
    public var maxRetries: Int
    public var stream: Bool
    public var normalized: ModelRetryNormalizedError
    public var providerAdvice: ModelRetryAdvice?

    public init(
        error: any Error,
        attempt: Int,
        maxRetries: Int,
        stream: Bool,
        normalized: ModelRetryNormalizedError,
        providerAdvice: ModelRetryAdvice? = nil
    ) {
        self.error = error
        self.attempt = attempt
        self.maxRetries = maxRetries
        self.stream = stream
        self.normalized = normalized
        self.providerAdvice = providerAdvice
    }
}

public typealias RetryPolicy = @Sendable (RetryPolicyContext) async throws -> RetryDecision

public struct ModelRetrySettings: Sendable {
    public var maxRetries: Int?
    public var backoff: ModelRetryBackoffSettings?
    public var policy: RetryPolicy?

    public init(
        maxRetries: Int? = nil,
        backoff: ModelRetryBackoffSettings? = nil,
        policy: RetryPolicy? = nil
    ) {
        self.maxRetries = maxRetries
        self.backoff = backoff
        self.policy = policy
    }

    public func resolve(_ override: ModelRetrySettings?) -> ModelRetrySettings {
        guard let override else {
            return self
        }
        return ModelRetrySettings(
            maxRetries: override.maxRetries ?? maxRetries,
            backoff: backoff?.resolve(override.backoff) ?? override.backoff,
            policy: override.policy ?? policy
        )
    }

    public func merging(_ override: ModelRetrySettings?) -> ModelRetrySettings {
        resolve(override)
    }

    public func toJSONDictionary() -> [String: JSONValue] {
        [
            "max_retries": maxRetries.map { .number(Double($0)) } ?? .null,
            "backoff": backoff.map { .object($0.toJSONDictionary()) } ?? .null
        ]
    }
}

extension ModelRetrySettings: Equatable {
    public static func == (lhs: ModelRetrySettings, rhs: ModelRetrySettings) -> Bool {
        lhs.maxRetries == rhs.maxRetries && lhs.backoff == rhs.backoff
    }
}

extension ModelRetrySettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case maxRetries = "max_retries"
        case backoff
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries)
        self.backoff = try container.decodeIfPresent(ModelRetryBackoffSettings.self, forKey: .backoff)
        self.policy = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(maxRetries, forKey: .maxRetries)
        try container.encodeIfPresent(backoff, forKey: .backoff)
    }
}

public enum RetryPolicies {
    public static func never() -> RetryPolicy {
        { _ in RetryDecision(retry: false) }
    }

    public static func providerSuggested() -> RetryPolicy {
        { context in
            guard let advice = context.providerAdvice, let suggested = advice.suggested else {
                return RetryDecision(retry: false)
            }
            if suggested == false {
                return RetryDecision.hardVeto(RetryDecision(retry: false, reason: advice.reason))
            }
            let decision = RetryDecision(retry: true, delay: advice.retryAfter, reason: advice.reason)
            if advice.replaySafety == .safe {
                return RetryDecision.replaySafe(decision)
            }
            return decision
        }
    }

    public static func networkError() -> RetryPolicy {
        { context in
            RetryDecision(retry: context.normalized.isNetworkError || context.normalized.isTimeout)
        }
    }

    public static func retryAfter() -> RetryPolicy {
        { context in
            let delay = context.normalized.retryAfter ?? context.providerAdvice?.retryAfter
            guard let delay else {
                return RetryDecision(retry: false)
            }
            return RetryDecision(retry: true, delay: delay)
        }
    }

    public static func httpStatus(_ statuses: Set<Int>) -> RetryPolicy {
        { context in
            guard let statusCode = context.normalized.statusCode else {
                return RetryDecision(retry: false)
            }
            return RetryDecision(retry: statuses.contains(statusCode))
        }
    }

    public static func all(_ policies: RetryPolicy...) -> RetryPolicy {
        guard !policies.isEmpty else {
            return never()
        }
        return { context in
            var merged = RetryDecision(retry: true)
            for policy in policies {
                let decision = try await policy(context)
                if decision.hardVeto || !decision.retry {
                    return decision
                }
                if let delay = decision.delay {
                    merged.delay = delay
                }
                if let reason = decision.reason {
                    merged.reason = reason
                }
                if decision.approvesReplay {
                    merged = RetryDecision.replaySafe(merged)
                }
            }
            return merged
        }
    }

    public static func any(_ policies: RetryPolicy...) -> RetryPolicy {
        guard !policies.isEmpty else {
            return never()
        }
        return { context in
            var firstPositive: RetryDecision?
            var lastNegative: RetryDecision?
            for policy in policies {
                let decision = try await policy(context)
                if decision.hardVeto {
                    return decision
                }
                if decision.retry {
                    firstPositive = mergePositive(firstPositive, decision)
                } else {
                    lastNegative = decision
                }
            }
            return firstPositive ?? lastNegative ?? RetryDecision(retry: false)
        }
    }

    private static func mergePositive(_ existing: RetryDecision?, _ incoming: RetryDecision) -> RetryDecision {
        guard var merged = existing else {
            return incoming
        }
        if let delay = incoming.delay {
            merged.delay = delay
        }
        if let reason = incoming.reason {
            merged.reason = reason
        }
        if incoming.approvesReplay {
            merged = RetryDecision.replaySafe(merged)
        }
        return merged
    }
}
