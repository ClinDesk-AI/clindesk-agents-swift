import Foundation

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
    case invalidModelResponse(String)
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
        case .invalidModelResponse(let reason):
            return "Invalid model response: \(reason)"
        case .approvalRejected(let toolName):
            return "Tool '\(toolName)' was not approved."
        case .cancelled:
            return "The run was cancelled."
        case .provider(let reason):
            return reason
        }
    }
}
