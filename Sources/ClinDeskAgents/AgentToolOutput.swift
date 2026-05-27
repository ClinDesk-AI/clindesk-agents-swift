enum AgentToolOutput {
    static func defaultOutput(from result: RunResult) -> String {
        if !result.finalOutput.isEmpty {
            return result.finalOutput
        }

        for item in result.newItems.reversed() {
            switch item {
            case .message(let message) where message.role == .assistant && !message.content.isEmpty:
                return message.content
            case .functionCallOutput(let output):
                if let text = output.output.stringValue, !text.isEmpty {
                    return text
                }
            default:
                continue
            }
        }

        return result.finalOutput
    }
}
