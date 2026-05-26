import Foundation

public struct TypedRunResult<Output: Sendable>: Sendable {
    public var finalOutput: Output
    public var rawFinalOutput: String
    public var lastAgentName: String
    public var trace: Trace
    public var newItems: [ModelInputItem]
    public var responseID: String?

    public init(
        finalOutput: Output,
        rawFinalOutput: String,
        lastAgentName: String,
        trace: Trace,
        newItems: [ModelInputItem],
        responseID: String? = nil
    ) {
        self.finalOutput = finalOutput
        self.rawFinalOutput = rawFinalOutput
        self.lastAgentName = lastAgentName
        self.trace = trace
        self.newItems = newItems
        self.responseID = responseID
    }
}

public enum StructuredOutput {
    public static func decode<Output: Decodable>(
        _ outputType: Output.Type,
        from rawOutput: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Output {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentsError.invalidStructuredOutput("Final output was not valid UTF-8.")
        }
        do {
            return try decoder.decode(outputType, from: data)
        } catch {
            throw AgentsError.invalidStructuredOutput(error.localizedDescription)
        }
    }
}
