import Foundation

enum ModelRetry {
    private static let defaultInitialDelay: TimeInterval = 0.25
    private static let defaultMaxDelay: TimeInterval = 2.0
    private static let defaultBackoffMultiplier = 2.0
    private static let defaultBackoffJitter = true
    private static let compatibilityConversationLockedRetries = 3

    static func getResponseWithRetry(
        getResponse: @Sendable () async throws -> ModelResponse,
        rewind: @Sendable () async throws -> Void = {},
        retrySettings: ModelRetrySettings?,
        getRetryAdvice: @Sendable (ModelRetryAdviceRequest) -> ModelRetryAdvice?
    ) async throws -> ModelResponse {
        var policyAttempt = 1
        var failedPolicyAttempts = 0

        while true {
            do {
                var response = try await getResponse()
                response.usage.applyRetryAttemptUsage(failedAttempts: failedPolicyAttempts)
                return response
            } catch {
                let providerAdvice = getRetryAdvice(ModelRetryAdviceRequest(
                    error: error,
                    attempt: policyAttempt,
                    stream: false
                ))
                let maxRetries = max(retrySettings?.maxRetries ?? 0, 0)
                let decision = try await evaluateRetry(
                    error: error,
                    attempt: policyAttempt,
                    maxRetries: maxRetries,
                    retryPolicy: retrySettings?.policy,
                    retryBackoff: retrySettings?.backoff,
                    stream: false,
                    providerAdvice: providerAdvice
                )
                guard decision.retry else {
                    throw error
                }

                try await rewind()
                try await sleep(for: decision.delay ?? 0)
                policyAttempt += 1
                failedPolicyAttempts += 1
            }
        }
    }

    private static func evaluateRetry(
        error: any Error,
        attempt: Int,
        maxRetries: Int,
        retryPolicy: RetryPolicy?,
        retryBackoff: ModelRetryBackoffSettings?,
        stream: Bool,
        providerAdvice: ModelRetryAdvice?
    ) async throws -> RetryDecision {
        guard attempt <= maxRetries else {
            return RetryDecision(retry: false)
        }

        let normalized = normalize(error: error, providerAdvice: providerAdvice)
        if normalized.isAbort || providerAdvice?.replaySafety == .unsafe {
            return RetryDecision(retry: false, reason: providerAdvice?.reason)
        }
        guard let retryPolicy else {
            return RetryDecision(retry: false)
        }

        let decision = try await retryPolicy(RetryPolicyContext(
            error: error,
            attempt: attempt,
            maxRetries: maxRetries,
            stream: stream,
            normalized: normalized,
            providerAdvice: providerAdvice
        ))
        guard decision.retry else {
            return decision
        }

        return RetryDecision(
            retry: true,
            delay: decision.delay ?? normalized.retryAfter ?? defaultRetryDelay(
                attempt: attempt,
                backoff: retryBackoff
            ),
            reason: decision.reason ?? providerAdvice?.reason
        )
    }

    private static func normalize(
        error: any Error,
        providerAdvice: ModelRetryAdvice?
    ) -> ModelRetryNormalizedError {
        var normalized = ModelRetryNormalizedError(
            statusCode: statusCode(error),
            errorCode: errorCode(error),
            message: String(describing: error),
            requestID: requestID(error),
            retryAfter: retryAfter(error),
            isAbort: error is CancellationError,
            isNetworkError: isNetworkError(error),
            isTimeout: isTimeout(error)
        )

        if let retryAfter = providerAdvice?.retryAfter {
            normalized.retryAfter = retryAfter
        }
        if let override = providerAdvice?.normalized {
            normalized = override
        }
        return normalized
    }

    private static func statusCode(_ error: any Error) -> Int? {
        if let error = error as? ProviderHTTPError {
            return error.statusCode
        }
        return nil
    }

    private static func errorCode(_ error: any Error) -> String? {
        if let error = error as? ProviderHTTPError {
            return error.errorCode
        }
        return nil
    }

    private static func requestID(_ error: any Error) -> String? {
        if let error = error as? ProviderHTTPError {
            return error.requestID
        }
        return nil
    }

    private static func isConversationLocked(_ error: any Error) -> Bool {
        errorCode(error) == "conversation_locked"
    }

    private static func shouldPreserveConversationLockedCompatibility(
        _ retrySettings: ModelRetrySettings?
    ) -> Bool {
        guard let retrySettings else {
            return true
        }
        guard let maxRetries = retrySettings.maxRetries else {
            return true
        }
        return maxRetries > 0
    }

    private static func retryAfter(_ error: any Error) -> TimeInterval? {
        guard let error = error as? ProviderHTTPError else {
            return nil
        }
        return parseRetryAfter(headers: error.headers)
    }

    private static func isNetworkError(_ error: any Error) -> Bool {
        if error is URLError {
            return true
        }
        let message = String(describing: error).lowercased()
        return message.contains("connection error")
            || message.contains("network error")
            || message.contains("socket hang up")
            || message.contains("connection closed")
    }

    private static func isTimeout(_ error: any Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        return false
    }

    private static func parseRetryAfter(headers: [String: String]) -> TimeInterval? {
        if let retryAfterMS = header(headers, "retry-after-ms"),
           let milliseconds = TimeInterval(retryAfterMS),
           milliseconds >= 0
        {
            return milliseconds / 1_000
        }
        guard let retryAfter = header(headers, "retry-after") else {
            return nil
        }
        if let seconds = TimeInterval(retryAfter), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: retryAfter) else {
            return nil
        }
        return max(date.timeIntervalSinceNow, 0)
    }

    private static func header(_ headers: [String: String], _ key: String) -> String? {
        let key = key.lowercased()
        for (name, value) in headers where name.lowercased() == key {
            return value
        }
        return nil
    }

    private static func defaultRetryDelay(
        attempt: Int,
        backoff: ModelRetryBackoffSettings?
    ) -> TimeInterval {
        let initialDelay = backoff?.initialDelay ?? defaultInitialDelay
        let maxDelay = backoff?.maxDelay ?? defaultMaxDelay
        let multiplier = backoff?.multiplier ?? defaultBackoffMultiplier
        let useJitter = backoff?.jitter ?? defaultBackoffJitter
        let base = min(initialDelay * pow(multiplier, Double(max(attempt - 1, 0))), maxDelay)
        guard useJitter else {
            return base
        }
        return min(max(base * Double.random(in: 0.875...1.125), 0), maxDelay)
    }

    private static func sleep(for delay: TimeInterval) async throws {
        guard delay > 0 else {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

}

public extension Usage {
    mutating func applyRetryAttemptUsage(failedAttempts: Int) {
        guard failedAttempts > 0 else {
            return
        }

        var successfulEntries = requestUsageEntries
        if successfulEntries.isEmpty {
            successfulEntries.append(RequestUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens,
                inputTokensDetails: inputTokensDetails,
                outputTokensDetails: outputTokensDetails
            ))
        }

        requests = max(requests, 1) + failedAttempts
        requestUsageEntries = Array(
            repeating: RequestUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            count: failedAttempts
        ) + successfulEntries
    }
}
