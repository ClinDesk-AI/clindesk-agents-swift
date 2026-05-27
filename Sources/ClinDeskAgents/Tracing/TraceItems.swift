import Foundation

public enum TraceItem: Equatable, Sendable {
    case agentStarted(String)
    case modelRequest(String)
    case modelResponse(ModelResponse)
    case toolCall(FunctionCall)
    case toolResult(FunctionCallOutput)
    case customToolCall(CustomToolCall)
    case customToolResult(CustomToolCallOutput)
    case computerCall(ComputerCall)
    case computerResult(ComputerCallOutput)
    case localShellCall(LocalShellCall)
    case localShellResult(LocalShellCallOutput)
    case shellCall(ShellCall)
    case shellResult(ShellCallOutput)
    case applyPatchCall(ApplyPatchCall)
    case applyPatchResult(ApplyPatchCallOutput)
    case handoff(String)
    case guardrail(String)
    case finalOutput(String)
}
