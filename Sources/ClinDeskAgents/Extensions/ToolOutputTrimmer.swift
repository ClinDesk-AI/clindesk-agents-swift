import Foundation

public struct ToolOutputTrimmer: Sendable {
    public var recentTurns: Int
    public var maxOutputChars: Int
    public var previewChars: Int
    public var trimmableTools: Set<String>?

    public init(
        recentTurns: Int = 2,
        maxOutputChars: Int = 500,
        previewChars: Int = 200,
        trimmableTools: Set<String>? = nil
    ) throws {
        guard recentTurns >= 1 else {
            throw AgentsError.invalidRunConfig("recentTurns must be >= 1, got \(recentTurns).")
        }
        guard maxOutputChars >= 1 else {
            throw AgentsError.invalidRunConfig("maxOutputChars must be >= 1, got \(maxOutputChars).")
        }
        guard previewChars >= 0 else {
            throw AgentsError.invalidRunConfig("previewChars must be >= 0, got \(previewChars).")
        }
        self.recentTurns = recentTurns
        self.maxOutputChars = maxOutputChars
        self.previewChars = previewChars
        self.trimmableTools = trimmableTools
    }

    public func filter<Context: Sendable>(_ data: CallModelData<Context>) async throws -> ModelInputData {
        let items = data.modelData.input
        guard !items.isEmpty else {
            return data.modelData
        }

        let boundary = findRecentBoundary(in: items)
        guard boundary > 0 else {
            return data.modelData
        }

        let callIDToNames = buildCallIDToNames(items)
        let newItems = items.enumerated().map { index, item in
            guard index < boundary else {
                return item
            }
            return trimmedItem(item, callIDToNames: callIDToNames) ?? item
        }

        return ModelInputData(input: newItems, instructions: data.modelData.instructions)
    }

    public func callAsFunction<Context: Sendable>(_ data: CallModelData<Context>) async throws -> ModelInputData {
        try await filter(data)
    }

    private func findRecentBoundary(in items: [ModelInputItem]) -> Int {
        var userMessageCount = 0
        for index in items.indices.reversed() {
            guard case .message(let message) = items[index], message.role == .user else {
                continue
            }
            userMessageCount += 1
            if userMessageCount >= recentTurns {
                return index
            }
        }
        return 0
    }

    private func buildCallIDToNames(_ items: [ModelInputItem]) -> [String: [String]] {
        var mapping: [String: [String]] = [:]
        for item in items {
            switch item {
            case .functionCall(let call):
                var names: [String] = []
                names.append(call.qualifiedName)
                if call.name != call.qualifiedName {
                    names.append(call.name)
                }
                mapping[call.callID] = names
            case .raw(let value):
                guard let type = value["type"]?.stringValue else {
                    continue
                }
                if type == "function_call",
                   let callID = value["call_id"]?.stringValue ?? value["id"]?.stringValue {
                    let qualifiedName = rawToolTraceName(value)
                    let bareName = rawToolName(value)
                    var names: [String] = []
                    if let qualifiedName {
                        names.append(qualifiedName)
                    }
                    if let bareName, bareName != qualifiedName {
                        names.append(bareName)
                    }
                    if !names.isEmpty {
                        mapping[callID] = names
                    }
                }
            default:
                continue
            }
        }
        return mapping
    }

    private func trimmedItem(
        _ item: ModelInputItem,
        callIDToNames: [String: [String]]
    ) -> ModelInputItem? {
        switch item {
        case .functionCallOutput(let output):
            let toolNames = callIDToNames[output.callID] ?? []
            guard shouldTrim(toolNames: toolNames),
                  let trimmedOutput = trimmedFunctionOutput(output.output, toolNames: toolNames)
            else {
                return nil
            }
            return .functionCallOutput(FunctionCallOutput(callID: output.callID, output: .string(trimmedOutput)))
        case .raw(let value):
            return trimmedRawItem(value, callIDToNames: callIDToNames).map(ModelInputItem.raw)
        default:
            return nil
        }
    }

    private func trimmedRawItem(
        _ value: JSONValue,
        callIDToNames: [String: [String]]
    ) -> JSONValue? {
        guard var object = value.objectValue,
              let type = object["type"]?.stringValue
        else {
            return nil
        }

        let callID = object["call_id"]?.stringValue ?? object["id"]?.stringValue ?? ""
        let toolNames = callIDToNames[callID] ?? []
        guard shouldTrim(toolNames: toolNames) else {
            return nil
        }

        switch type {
        case "function_call_output":
            guard let output = object["output"],
                  let trimmedOutput = trimmedFunctionOutput(output, toolNames: toolNames)
            else {
                return nil
            }
            object["output"] = .string(trimmedOutput)
            return .object(object)
        default:
            return nil
        }
    }

    private func shouldTrim(toolNames: [String]) -> Bool {
        guard let trimmableTools else {
            return true
        }
        return toolNames.contains { trimmableTools.contains($0) }
    }

    private func trimmedFunctionOutput(_ output: JSONValue, toolNames: [String]) -> String? {
        let outputString = stringValue(for: output)
        let outputLength = outputString.count
        guard outputLength > maxOutputChars else {
            return nil
        }

        let toolName = toolNames.first ?? "unknown_tool"
        let preview = String(outputString.prefix(previewChars))
        let summary = "[Trimmed: \(toolName) output — \(outputLength) chars → \(previewChars) char preview]\n\(preview)..."
        guard summary.count < outputLength else {
            return nil
        }
        return summary
    }

    private func trimJSONSchema(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var trimmed: [String: JSONValue] = [:]
            for (key, value) in object {
                if ["description", "title", "$comment", "examples"].contains(key) {
                    continue
                }
                trimmed[key] = trimJSONSchema(value)
            }
            return .object(trimmed)
        case .array(let array):
            return .array(array.map(trimJSONSchema))
        case .null,
                .bool,
                .number,
                .string:
            return value
        }
    }

    private func stringValue(for value: JSONValue) -> String {
        value.stringValue ?? value.prettyPrinted()
    }

    private func rawToolTraceName(_ value: JSONValue) -> String? {
        if let namespace = value["namespace"]?.stringValue, !namespace.isEmpty,
           let name = value["name"]?.stringValue, !name.isEmpty {
            return "\(namespace).\(name)"
        }
        return value["name"]?.stringValue
    }

    private func rawToolName(_ value: JSONValue) -> String? {
        value["name"]?.stringValue
    }
}
