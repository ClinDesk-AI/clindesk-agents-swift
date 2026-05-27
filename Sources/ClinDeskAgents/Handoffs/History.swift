import Foundation

public enum HandoffHistory {
    public static let defaultConversationHistoryStart = "<CONVERSATION HISTORY>"
    public static let defaultConversationHistoryEnd = "</CONVERSATION HISTORY>"

    private static let storage = HandoffHistoryStorage()

    public static func setConversationHistoryWrappers(start: String? = nil, end: String? = nil) {
        storage.set(start: start, end: end)
    }

    public static func resetConversationHistoryWrappers() {
        storage.reset()
    }

    public static func conversationHistoryWrappers() -> (start: String, end: String) {
        storage.get()
    }

    public static func nestHandoffHistory<Context: Sendable>(
        _ handoffInputData: HandoffInputData<Context>,
        historyMapper: HandoffHistoryMapper? = nil
    ) async throws -> HandoffInputData<Context> {
        let normalizedHistory = flattenNestedHistoryMessages(handoffInputData.inputHistory)

        var preItemsAsInputs: [ModelInputItem] = []
        var filteredPreItems: [ModelInputItem] = []
        for item in handoffInputData.preHandoffItems {
            preItemsAsInputs.append(item)
            if shouldForwardPreItem(item) {
                filteredPreItems.append(item)
            }
        }

        var newItemsAsInputs: [ModelInputItem] = []
        var filteredInputItems: [ModelInputItem] = []
        for item in handoffInputData.newItems {
            newItemsAsInputs.append(item)
            if shouldForwardNewItem(item) {
                filteredInputItems.append(item)
            }
        }

        let transcript = normalizedHistory + preItemsAsInputs + newItemsAsInputs
        let historyItems = try await (historyMapper ?? defaultHandoffHistoryMapper)(transcript)

        return handoffInputData.clone(
            inputHistory: historyItems,
            preHandoffItems: filteredPreItems,
            inputItems: filteredInputItems
        )
    }

    public static func defaultHandoffHistoryMapper(_ transcript: [ModelInputItem]) -> [ModelInputItem] {
        let summaryMessage = buildSummaryMessage(transcript)
        return [.message(AgentMessage(role: .assistant, content: summaryMessage))]
    }

    private static func buildSummaryMessage(_ transcript: [ModelInputItem]) -> String {
        let summaryLines: [String]
        if transcript.isEmpty {
            summaryLines = ["(no previous turns recorded)"]
        } else {
            summaryLines = transcript.enumerated().map { index, item in
                "\(index + 1). \(formatTranscriptItem(item))"
            }
        }

        let wrappers = conversationHistoryWrappers()
        return ([
            "For context, here is the conversation so far between the user and the previous agent:",
            wrappers.start
        ] + summaryLines + [
            wrappers.end
        ]).joined(separator: "\n")
    }

    private static func formatTranscriptItem(_ item: ModelInputItem) -> String {
        if case .message(let message) = item,
           !message.content.contains("\n"),
           !message.content.contains("\r") {
            return "\(message.role.rawValue): \(message.content)"
        }
        return summaryPayload(for: item).prettyPrinted()
    }

    private static func flattenNestedHistoryMessages(_ items: [ModelInputItem]) -> [ModelInputItem] {
        var flattened: [ModelInputItem] = []
        for item in items {
            if let nestedTranscript = extractNestedHistoryTranscript(from: item) {
                flattened.append(contentsOf: nestedTranscript)
            } else {
                flattened.append(item)
            }
        }
        return flattened
    }

    private static func extractNestedHistoryTranscript(from item: ModelInputItem) -> [ModelInputItem]? {
        guard case .message(let message) = item else {
            return nil
        }
        let wrappers = conversationHistoryWrappers()
        guard let startRange = message.content.range(of: wrappers.start),
              let endRange = message.content.range(of: wrappers.end, options: .backwards),
              startRange.upperBound <= endRange.lowerBound
        else {
            return nil
        }

        let body = String(message.content[startRange.upperBound..<endRange.lowerBound])
        let parsed = splitSummaryRecords(body).compactMap(parseSummaryLine)
        return parsed.isEmpty ? nil : parsed
    }

    private static func splitSummaryRecords(_ body: String) -> [String] {
        var records: [String] = []
        var current: [String] = []
        var currentIsNumbered = false

        for rawLine in body.split(whereSeparator: \.isNewline).map(String.init) {
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let startsNumberedRecord = startsNumberedSummaryRecord(rawLine)
            if current.isEmpty {
                current = [rawLine.trimmingCharacters(in: .whitespacesAndNewlines)]
                currentIsNumbered = startsNumberedRecord
            } else if startsNumberedRecord || !currentIsNumbered {
                records.append(current.joined(separator: "\n"))
                current = [rawLine.trimmingCharacters(in: .whitespacesAndNewlines)]
                currentIsNumbered = startsNumberedRecord
            } else {
                current.append(rawLine.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if !current.isEmpty {
            records.append(current.joined(separator: "\n"))
        }
        return records
    }

    private static func startsNumberedSummaryRecord(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = stripped.firstIndex(of: ".") else {
            return false
        }
        return stripped[..<dotIndex].allSatisfy(\.isNumber)
    }

    private static func parseSummaryLine(_ line: String) -> ModelInputItem? {
        let stripped = stripSummaryLineNumber(line.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !stripped.isEmpty else {
            return nil
        }
        if let data = stripped.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           let item = modelInputItem(fromSummaryPayload: value) {
            return item
        }

        let parts = stripped.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        let role = AgentMessage.Role(rawValue: parts[0].trimmingCharacters(in: .whitespaces))
            ?? .developer
        let content = parts[1].trimmingCharacters(in: .whitespaces)
        return .message(AgentMessage(role: role, content: content))
    }

    private static func stripSummaryLineNumber(_ value: String) -> String {
        guard let dotIndex = value.firstIndex(of: "."),
              value[..<dotIndex].allSatisfy(\.isNumber)
        else {
            return value
        }
        return value[value.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
    }

    private static func shouldForwardPreItem(_ item: ModelInputItem) -> Bool {
        if case .message(let message) = item, message.role == .assistant {
            return false
        }
        return !isSummaryOnly(item)
    }

    private static func shouldForwardNewItem(_ item: ModelInputItem) -> Bool {
        if case .message = item {
            return true
        }
        return !isSummaryOnly(item)
    }

    private static func isSummaryOnly(_ item: ModelInputItem) -> Bool {
        switch item {
        case .functionCall,
                .functionCallOutput,
                .computerCall,
                .computerCallOutput,
                .localShellCall,
                .localShellCallOutput,
                .shellCall,
                .shellCallOutput,
                .applyPatchCall,
                .applyPatchCallOutput,
                .reasoning:
            return true
        case .raw(let value):
            guard let type = value["type"]?.stringValue else {
                return false
            }
            return ["function_call", "function_call_output", "reasoning"].contains(type)
        case .message,
                .customToolCall,
                .customToolCallOutput,
                .refusal:
            return false
        }
    }

    private static func summaryPayload(for item: ModelInputItem) -> JSONValue {
        switch item {
        case .message(let message):
            return [
                "role": .string(message.role.rawValue),
                "content": .string(message.content)
            ]
        case .functionCall(let call):
            return [
                "type": "function_call",
                "call_id": .string(call.callID),
                "name": .string(call.name),
                "arguments": call.arguments
            ]
        case .functionCallOutput(let output):
            return [
                "type": "function_call_output",
                "call_id": .string(output.callID),
                "output": output.output
            ]
        case .customToolCall(let call):
            return [
                "type": "custom_tool_call",
                "call_id": .string(call.callID),
                "name": .string(call.name),
                "input": .string(call.input)
            ]
        case .customToolCallOutput(let output):
            return [
                "type": "custom_tool_call_output",
                "call_id": .string(output.callID),
                "output": .string(output.output)
            ]
        case .computerCall(let call):
            var payload: [String: JSONValue] = [
                "type": "computer_call",
                "call_id": .string(call.callID)
            ]
            if !call.actions.isEmpty {
                payload["actions"] = .array(call.actions.map {
                    (try? JSONValue.encoded($0)) ?? .emptyObject
                })
            } else if let action = call.action {
                payload["action"] = (try? JSONValue.encoded(action)) ?? .emptyObject
            }
            return .object(payload)
        case .computerCallOutput(let output):
            var payload: [String: JSONValue] = [
                "type": "computer_call_output",
                "call_id": .string(output.callID),
                "output": output.output
            ]
            if let checks = output.acknowledgedSafetyChecks {
                payload["acknowledged_safety_checks"] = .array(checks.map {
                    (try? JSONValue.encoded($0)) ?? .emptyObject
                })
            }
            return .object(payload)
        case .localShellCall(let call):
            return [
                "type": "local_shell_call",
                "call_id": .string(call.callID),
                "action": call.action
            ]
        case .localShellCallOutput(let output):
            return [
                "type": "local_shell_call_output",
                "call_id": .string(output.callID),
                "output": .string(output.output)
            ]
        case .shellCall(let call):
            return [
                "type": "shell_call",
                "call_id": .string(call.callID),
                "action": (try? JSONValue.encoded(call.action)) ?? .emptyObject
            ]
        case .shellCallOutput(let output):
            return [
                "type": "shell_call_output",
                "call_id": .string(output.callID),
                "output": output.output
            ]
        case .applyPatchCall(let call):
            return [
                "type": "apply_patch_call",
                "call_id": .string(call.callID),
                "operations": .array(call.operations.map {
                    (try? JSONValue.encoded($0)) ?? .emptyObject
                })
            ]
        case .applyPatchCallOutput(let output):
            return [
                "type": "apply_patch_call_output",
                "call_id": .string(output.callID),
                "status": .string(output.status.rawValue),
                "output": .string(output.output)
            ]
        case .refusal(let refusal):
            return [
                "type": "refusal",
                "refusal": .string(refusal)
            ]
        case .reasoning(let value):
            return [
                "type": "reasoning",
                "content": value
            ]
        case .raw(let value):
            return removingProviderData(from: value)
        }
    }

    private static func modelInputItem(fromSummaryPayload value: JSONValue) -> ModelInputItem? {
        let value = removingProviderData(from: value)
        if let role = value["role"]?.stringValue,
           let content = value["content"]?.stringValue,
           let messageRole = AgentMessage.Role(rawValue: role) {
            return .message(AgentMessage(role: messageRole, content: content))
        }

        guard let type = value["type"]?.stringValue else {
            return .raw(value)
        }
        switch type {
        case "function_call":
            return .functionCall(FunctionCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                name: value["name"]?.stringValue ?? "",
                arguments: value["arguments"] ?? .emptyObject
            ))
        case "function_call_output":
            return .functionCallOutput(FunctionCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                output: value["output"] ?? .null
            ))
        case "custom_tool_call":
            return .customToolCall(CustomToolCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                name: value["name"]?.stringValue ?? "",
                input: value["input"]?.stringValue ?? ""
            ))
        case "custom_tool_call_output":
            return .customToolCallOutput(CustomToolCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                output: value["output"]?.stringValue ?? ""
            ))
        case "computer_call":
            let actions: [ComputerAction]
            if case .array(let values) = value["actions"] {
                let decoded = values.compactMap { try? $0.decoded(ComputerAction.self) }
                actions = decoded.count == values.count ? decoded : []
            } else {
                actions = []
            }
            let action = (try? (value["action"] ?? .null).decoded(ComputerAction.self))
            return .computerCall(ComputerCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                action: action,
                actions: actions
            ))
        case "computer_call_output":
            let checks: [PendingComputerSafetyCheck]?
            if case .array(let values) = value["acknowledged_safety_checks"] {
                let decoded = values.compactMap { try? $0.decoded(PendingComputerSafetyCheck.self) }
                checks = decoded.count == values.count ? decoded : nil
            } else {
                checks = nil
            }
            return .computerCallOutput(ComputerCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                output: value["output"] ?? .null,
                acknowledgedSafetyChecks: checks
            ))
        case "local_shell_call":
            return .localShellCall(LocalShellCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                action: value["action"] ?? .emptyObject
            ))
        case "local_shell_call_output":
            return .localShellCallOutput(LocalShellCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                output: value["output"]?.stringValue ?? ""
            ))
        case "shell_call":
            guard let action = try? (value["action"] ?? .emptyObject).decoded(ShellActionRequest.self) else {
                return .raw(value)
            }
            return .shellCall(ShellCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                action: action
            ))
        case "shell_call_output":
            return .shellCallOutput(ShellCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                output: value["output"] ?? .null
            ))
        case "apply_patch_call":
            let operations: [ApplyPatchOperation]?
            if case .array(let values) = value["operations"] {
                let decoded = values.compactMap { try? $0.decoded(ApplyPatchOperation.self) }
                operations = decoded.count == values.count ? decoded : nil
            } else if let operation = value["operation"] {
                operations = (try? operation.decoded(ApplyPatchOperation.self)).map { [$0] }
            } else {
                operations = nil
            }
            guard let operations else {
                return .raw(value)
            }
            return .applyPatchCall(ApplyPatchCall(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                operations: operations
            ))
        case "apply_patch_call_output":
            return .applyPatchCallOutput(ApplyPatchCallOutput(
                callID: value["call_id"]?.stringValue ?? UUID().uuidString,
                status: ApplyPatchStatus(rawValue: value["status"]?.stringValue ?? "") ?? .completed,
                output: value["output"]?.stringValue ?? ""
            ))
        case "refusal":
            return .refusal(value["refusal"]?.stringValue ?? "")
        case "reasoning":
            return .reasoning(value["content"] ?? .emptyObject)
        default:
            return .raw(value)
        }
    }

    private static func removingProviderData(from value: JSONValue) -> JSONValue {
        guard case .object(var object) = value else {
            return value
        }
        object.removeValue(forKey: "provider_data")
        return .object(object)
    }
}

private final class HandoffHistoryStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var start = HandoffHistory.defaultConversationHistoryStart
    private var end = HandoffHistory.defaultConversationHistoryEnd

    func set(start: String?, end: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let start {
            self.start = start
        }
        if let end {
            self.end = end
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        start = HandoffHistory.defaultConversationHistoryStart
        end = HandoffHistory.defaultConversationHistoryEnd
    }

    func get() -> (start: String, end: String) {
        lock.lock()
        defer { lock.unlock() }
        return (start, end)
    }
}
