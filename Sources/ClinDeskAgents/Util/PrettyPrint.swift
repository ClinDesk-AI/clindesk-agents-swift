import Foundation

private func indent(_ text: String, level: Int) -> String {
    let prefix = String(repeating: "  ", count: level)
    return text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "\(prefix)\($0)" }
        .joined(separator: "\n")
}

private func prettyEncodedOutput<Output: Encodable>(_ output: Output) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(output),
          let string = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    return string
}

public func prettyPrintResult(_ result: RunResult) -> String {
    var output = "RunResult:"
    output += "\n- Last agent: Agent(name=\"\(result.lastAgentName)\", ...)"
    output += "\n- Final output (String):\n\(indent(result.finalOutput, level: 2))"
    output += "\n- \(result.newItems.count) new item(s)"
    output += "\n- \(result.modelResponses.count) model response(s)"
    output += "\n- \(result.inputGuardrailResults.count) input guardrail result(s)"
    output += "\n- \(result.outputGuardrailResults.count) output guardrail result(s)"
    output += "\n(See `RunResult` for more details)"
    return output
}

public func prettyPrintResult<Output: Encodable & Sendable>(_ result: TypedRunResult<Output>) -> String {
    let finalOutput = prettyEncodedOutput(result.finalOutput) ?? String(describing: result.finalOutput)
    var output = "TypedRunResult:"
    output += "\n- Last agent: Agent(name=\"\(result.lastAgentName)\", ...)"
    output += "\n- Final output (\(String(describing: Output.self))):\n\(indent(finalOutput, level: 2))"
    output += "\n- \(result.newItems.count) new item(s)"
    output += "\n- \(result.modelResponses.count) model response(s)"
    output += "\n- \(result.inputGuardrailResults.count) input guardrail result(s)"
    output += "\n- \(result.outputGuardrailResults.count) output guardrail result(s)"
    output += "\n(See `TypedRunResult` for more details)"
    return output
}

public func prettyPrintRunResultStreaming<Context: Sendable>(_ result: RunResultStreaming<Context>) -> String {
    let finalOutput = result.finalOutput ?? "None"
    let finalOutputType = result.finalOutput == nil ? "None" : "String"
    var output = "RunResultStreaming:"
    output += "\n- Current agent: Agent(name=\"\(result.currentAgent.name)\", ...)"
    output += "\n- Current turn: \(result.currentTurn)"
    output += "\n- Max turns: \(result.maxTurns.map(String.init) ?? "nil")"
    output += "\n- Is complete: \(result.isComplete)"
    output += "\n- Final output (\(finalOutputType)):\n\(indent(finalOutput, level: 2))"
    output += "\n- \(result.newItems.count) new item(s)"
    output += "\n- \(result.modelResponses.count) model response(s)"
    output += "\n- \(result.inputGuardrailResults.count) input guardrail result(s)"
    output += "\n- \(result.outputGuardrailResults.count) output guardrail result(s)"
    output += "\n(See `RunResultStreaming` for more details)"
    return output
}

public func prettyPrintRunErrorDetails<Context: Sendable>(_ details: RunErrorDetails<Context>) -> String {
    var output = "RunErrorDetails:"
    output += "\n- Last agent: Agent(name=\"\(details.lastAgent.name)\", ...)"
    output += "\n- \(details.newItems.count) new item(s)"
    output += "\n- \(details.modelResponses.count) model response(s)"
    output += "\n- \(details.inputGuardrailResults.count) input guardrail result(s)"
    output += "\n- \(details.outputGuardrailResults.count) output guardrail result(s)"
    output += "\n(See `RunErrorDetails` for more details)"
    return output
}

public extension RunResult {
    func prettyPrinted() -> String {
        prettyPrintResult(self)
    }
}

extension RunResultStreaming: CustomStringConvertible {
    public var description: String {
        prettyPrintRunResultStreaming(self)
    }
}

public extension RunResultStreaming {
    func prettyPrinted() -> String {
        prettyPrintRunResultStreaming(self)
    }
}

public extension RunErrorData {
    func prettyPrinted() -> String {
        prettyPrintRunErrorDetails(self)
    }
}

public extension TypedRunResult where Output: Encodable {
    func prettyPrinted() -> String {
        prettyPrintResult(self)
    }
}
