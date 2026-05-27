import Foundation

public struct ProviderHTTPError: Error, Equatable, LocalizedError, Sendable {
    public var statusCode: Int
    public var body: String
    public var requestID: String?
    public var headers: [String: String]
    public var errorCode: String?

    public init(
        statusCode: Int,
        body: String,
        requestID: String? = nil,
        headers: [String: String] = [:],
        errorCode: String? = nil
    ) {
        self.statusCode = statusCode
        self.body = body
        self.requestID = requestID
        self.headers = headers
        self.errorCode = errorCode
    }

    public var errorDescription: String? {
        "Provider returned HTTP \(statusCode): \(body)"
    }
}

public struct ToolTimeoutError: Error, Equatable, LocalizedError, Sendable {
    public var toolName: String
    public var timeoutSeconds: TimeInterval

    public init(toolName: String, timeoutSeconds: TimeInterval) {
        self.toolName = toolName
        self.timeoutSeconds = timeoutSeconds
    }

    public var errorDescription: String? {
        Self.defaultMessage(toolName: toolName, timeoutSeconds: timeoutSeconds)
    }

    public static func defaultMessage(toolName: String, timeoutSeconds: TimeInterval) -> String {
        "Tool '\(toolName)' timed out after \(formattedSeconds(timeoutSeconds)) seconds."
    }

    private static func formattedSeconds(_ seconds: TimeInterval) -> String {
        let wholeSeconds = seconds.rounded(.towardZero)
        if seconds == wholeSeconds {
            return String(Int(wholeSeconds))
        }
        return String(seconds)
    }
}

public enum AgentsError: Error, Equatable, LocalizedError, Sendable {
    case missingModel(agentName: String)
    case modelNotFound(String)
    case maxTurnsExceeded(Int)
    case toolNotFound(String)
    case toolInputRejected(toolName: String, reason: String)
    case toolOutputRejected(toolName: String, reason: String)
    case inputGuardrailTripwire(name: String, reason: String)
    case outputGuardrailTripwire(name: String, reason: String)
    case invalidToolArguments(toolName: String, reason: String)
    case invalidToolOutput(String)
    case invalidModelResponse(String)
    case modelRefusal(String)
    case invalidStructuredOutput(String)
    case invalidRunConfig(String)
    case approvalRejected(toolName: String)
    case cancelled
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .missingModel(let agentName):
            return "No model was configured for agent '\(agentName)'."
        case .modelNotFound(let modelName):
            return "No model provider could resolve '\(modelName)'."
        case .maxTurnsExceeded(let maxTurns):
            return "The run exceeded the maximum turn count of \(maxTurns)."
        case .toolNotFound(let name):
            return "The model requested an unknown tool named '\(name)'."
        case .toolInputRejected(let toolName, let reason):
            return "Tool input for '\(toolName)' was rejected: \(reason)"
        case .toolOutputRejected(let toolName, let reason):
            return "Tool output for '\(toolName)' was rejected: \(reason)"
        case .inputGuardrailTripwire(let name, let reason):
            return "Input guardrail '\(name)' stopped the run: \(reason)"
        case .outputGuardrailTripwire(let name, let reason):
            return "Output guardrail '\(name)' stopped the run: \(reason)"
        case .invalidToolArguments(let toolName, let reason):
            return "Invalid arguments for tool '\(toolName)': \(reason)"
        case .invalidToolOutput(let reason):
            return "Invalid tool output: \(reason)"
        case .invalidModelResponse(let reason):
            return "Invalid model response: \(reason)"
        case .modelRefusal(let refusal):
            return "Model refused to produce output: \(refusal)"
        case .invalidStructuredOutput(let reason):
            return "Invalid structured output: \(reason)"
        case .invalidRunConfig(let reason):
            return "Invalid run configuration: \(reason)"
        case .approvalRejected:
            return defaultApprovalRejectionMessage
        case .cancelled:
            return "The run was cancelled."
        case .provider(let reason):
            return reason
        }
    }
}
