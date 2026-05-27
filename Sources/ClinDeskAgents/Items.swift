import Foundation

public struct AgentMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case developer
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct FunctionCall: Codable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var name: String
    public var namespace: String?
    public var arguments: JSONValue
    public var toolOrigin: ToolOrigin?

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        name: String,
        namespace: String? = nil,
        arguments: JSONValue,
        toolOrigin: ToolOrigin? = nil
    ) {
        self.id = id
        self.callID = callID
        self.name = name
        self.namespace = namespace
        self.arguments = arguments
        self.toolOrigin = toolOrigin
    }

    public var qualifiedName: String {
        guard let namespace, !namespace.isEmpty else {
            return name
        }
        return "\(namespace).\(name)"
    }

    public func withToolOrigin(_ toolOrigin: ToolOrigin?) -> FunctionCall {
        var copy = self
        copy.toolOrigin = toolOrigin
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case name
        case namespace
        case arguments
        case toolOrigin = "tool_origin"
    }
}

extension FunctionCall: Equatable {
    public static func == (lhs: FunctionCall, rhs: FunctionCall) -> Bool {
        lhs.id == rhs.id
            && lhs.callID == rhs.callID
            && lhs.name == rhs.name
            && lhs.namespace == rhs.namespace
            && lhs.arguments == rhs.arguments
    }
}

public struct FunctionCallOutput: Codable, Sendable {
    public var callID: String
    public var output: JSONValue
    public var toolOrigin: ToolOrigin?

    public init(callID: String, output: JSONValue, toolOrigin: ToolOrigin? = nil) {
        self.callID = callID
        self.output = output
        self.toolOrigin = toolOrigin
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case output
        case toolOrigin = "tool_origin"
    }
}

extension FunctionCallOutput: Equatable {
    public static func == (lhs: FunctionCallOutput, rhs: FunctionCallOutput) -> Bool {
        lhs.callID == rhs.callID
            && lhs.output == rhs.output
    }
}

public struct CustomToolCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var callID: String
    public var name: String
    public var input: String

    public init(
        id: String = UUID().uuidString,
        callID: String = UUID().uuidString,
        name: String,
        input: String
    ) {
        self.id = id
        self.callID = callID
        self.name = name
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case name
        case input
    }
}

public struct CustomToolCallOutput: Codable, Equatable, Sendable {
    public var callID: String
    public var output: String

    public init(callID: String, output: String) {
        self.callID = callID
        self.output = output
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case output
    }
}

public enum ModelInputItem: Codable, Equatable, Sendable {
    case message(AgentMessage)
    case functionCall(FunctionCall)
    case functionCallOutput(FunctionCallOutput)
    case customToolCall(CustomToolCall)
    case customToolCallOutput(CustomToolCallOutput)
    case computerCall(ComputerCall)
    case computerCallOutput(ComputerCallOutput)
    case localShellCall(LocalShellCall)
    case localShellCallOutput(LocalShellCallOutput)
    case shellCall(ShellCall)
    case shellCallOutput(ShellCallOutput)
    case applyPatchCall(ApplyPatchCall)
    case applyPatchCallOutput(ApplyPatchCallOutput)
    case refusal(String)
    case reasoning(JSONValue)
    case raw(JSONValue)
}

public enum ModelOutputItem: Codable, Equatable, Sendable {
    case message(AgentMessage)
    case functionCall(FunctionCall)
    case customToolCall(CustomToolCall)
    case computerCall(ComputerCall)
    case localShellCall(LocalShellCall)
    case shellCall(ShellCall)
    case applyPatchCall(ApplyPatchCall)
    case refusal(String)
    case reasoning(JSONValue)
    case raw(JSONValue)
}

public extension ModelInputItem {
    init(from decoder: Decoder) throws {
        self = try decodeModelItem(from: decoder, outputOnly: false).input
    }

    func encode(to encoder: Encoder) throws {
        try encodeModelItem(self, to: encoder)
    }
}

public extension ModelOutputItem {
    init(from decoder: Decoder) throws {
        guard let output = try decodeModelItem(from: decoder, outputOnly: true).output else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Item is not a model output item.")
            )
        }
        self = output
    }

    func encode(to encoder: Encoder) throws {
        try encodeModelItem(self, to: encoder)
    }
}

private struct ModelItemPair {
    var input: ModelInputItem
    var output: ModelOutputItem?
}

private enum ModelItemCodingKeys: String, CodingKey {
    case type
    case refusal
}

private func decodeModelItem(from decoder: Decoder, outputOnly: Bool) throws -> ModelItemPair {
    let raw = try JSONValue(from: decoder)
    guard case .object(let object) = raw else {
        return ModelItemPair(input: .raw(raw), output: .raw(raw))
    }

    if let legacy = try decodeLegacyModelItem(object: object, outputOnly: outputOnly) {
        return legacy
    }

    let type = object["type"]?.stringValue
    switch type {
    case "message":
        let message = try decodeModelItemPayload(AgentMessage.self, from: raw)
        return ModelItemPair(input: .message(message), output: .message(message))
    case "function_call":
        let call = try decodeModelItemPayload(FunctionCall.self, from: raw)
        return ModelItemPair(input: .functionCall(call), output: .functionCall(call))
    case "function_call_output":
        let output = try decodeModelItemPayload(FunctionCallOutput.self, from: raw)
        return ModelItemPair(input: .functionCallOutput(output), output: nil)
    case "custom_tool_call":
        let call = try decodeModelItemPayload(CustomToolCall.self, from: raw)
        return ModelItemPair(input: .customToolCall(call), output: .customToolCall(call))
    case "custom_tool_call_output":
        let output = try decodeModelItemPayload(CustomToolCallOutput.self, from: raw)
        return ModelItemPair(input: .customToolCallOutput(output), output: nil)
    case "computer_call":
        let call = try decodeModelItemPayload(ComputerCall.self, from: raw)
        return ModelItemPair(input: .computerCall(call), output: .computerCall(call))
    case "computer_call_output":
        let output = try decodeModelItemPayload(ComputerCallOutput.self, from: raw)
        return ModelItemPair(input: .computerCallOutput(output), output: nil)
    case "local_shell_call":
        let call = try decodeModelItemPayload(LocalShellCall.self, from: raw)
        return ModelItemPair(input: .localShellCall(call), output: .localShellCall(call))
    case "local_shell_call_output":
        let output = try decodeModelItemPayload(LocalShellCallOutput.self, from: raw)
        return ModelItemPair(input: .localShellCallOutput(output), output: nil)
    case "shell_call":
        let call = try decodeModelItemPayload(ShellCall.self, from: raw)
        return ModelItemPair(input: .shellCall(call), output: .shellCall(call))
    case "shell_call_output":
        let output = try decodeModelItemPayload(ShellCallOutput.self, from: raw)
        return ModelItemPair(input: .shellCallOutput(output), output: nil)
    case "apply_patch_call":
        let call = try decodeModelItemPayload(ApplyPatchCall.self, from: raw)
        return ModelItemPair(input: .applyPatchCall(call), output: .applyPatchCall(call))
    case "apply_patch_call_output":
        let output = try decodeModelItemPayload(ApplyPatchCallOutput.self, from: raw)
        return ModelItemPair(input: .applyPatchCallOutput(output), output: nil)
    case "refusal":
        let refusal = object["refusal"]?.stringValue ?? ""
        return ModelItemPair(input: .refusal(refusal), output: .refusal(refusal))
    case "reasoning":
        return ModelItemPair(input: .reasoning(raw), output: .reasoning(raw))
    default:
        return ModelItemPair(input: .raw(raw), output: .raw(raw))
    }
}

private func decodeLegacyModelItem(object: [String: JSONValue], outputOnly: Bool) throws -> ModelItemPair? {
    if let value = object["message"] {
        let message = try decodeModelItemPayload(AgentMessage.self, from: value)
        return ModelItemPair(input: .message(message), output: .message(message))
    }
    if let value = object["functionCall"] {
        let call = try decodeModelItemPayload(FunctionCall.self, from: value)
        return ModelItemPair(input: .functionCall(call), output: .functionCall(call))
    }
    if let value = object["functionCallOutput"], !outputOnly {
        let output = try decodeModelItemPayload(FunctionCallOutput.self, from: value)
        return ModelItemPair(input: .functionCallOutput(output), output: nil)
    }
    if let value = object["refusal"] {
        let refusal = try decodeModelItemPayload(String.self, from: value)
        return ModelItemPair(input: .refusal(refusal), output: .refusal(refusal))
    }
    if let value = object["reasoning"] {
        return ModelItemPair(input: .reasoning(value), output: .reasoning(value))
    }
    if let value = object["raw"] {
        return ModelItemPair(input: .raw(value), output: .raw(value))
    }
    return nil
}

private func encodeModelItem(_ item: ModelInputItem, to encoder: Encoder) throws {
    let value: JSONValue
    switch item {
    case .message(let message):
        value = try encodeModelItemPayload(message, type: "message")
    case .functionCall(let call):
        value = try encodeModelItemPayload(call, type: "function_call")
    case .functionCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "function_call_output")
    case .customToolCall(let call):
        value = try encodeModelItemPayload(call, type: "custom_tool_call")
    case .customToolCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "custom_tool_call_output")
    case .computerCall(let call):
        value = try encodeModelItemPayload(call, type: "computer_call")
    case .computerCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "computer_call_output")
    case .localShellCall(let call):
        value = try encodeModelItemPayload(call, type: "local_shell_call")
    case .localShellCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "local_shell_call_output")
    case .shellCall(let call):
        value = try encodeModelItemPayload(call, type: "shell_call")
    case .shellCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "shell_call_output")
    case .applyPatchCall(let call):
        value = try encodeModelItemPayload(call, type: "apply_patch_call")
    case .applyPatchCallOutput(let output):
        value = try encodeModelItemPayload(output, type: "apply_patch_call_output")
    case .refusal(let refusal):
        value = .object(["type": .string("refusal"), "refusal": .string(refusal)])
    case .reasoning(let raw), .raw(let raw):
        value = raw
    }
    try value.encode(to: encoder)
}

private func encodeModelItem(_ item: ModelOutputItem, to encoder: Encoder) throws {
    try encodeModelItem(item.inputItem, to: encoder)
}

private func encodeModelItemPayload<T: Encodable>(_ payload: T, type: String) throws -> JSONValue {
    let encoded = try JSONValue.encoded(payload)
    guard case .object(var object) = encoded else {
        return ["type": .string(type), "value": encoded]
    }
    object["type"] = .string(type)
    return .object(object)
}

private func decodeModelItemPayload<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

public struct ModelResponse: Codable, Equatable, Sendable {
    public var output: [ModelOutputItem]
    public var usage: Usage
    public var responseID: String?
    public var requestID: String?
    public var raw: JSONValue?

    public init(
        output: [ModelOutputItem],
        usage: Usage = Usage(),
        responseID: String? = nil,
        requestID: String? = nil,
        raw: JSONValue? = nil
    ) {
        self.output = output
        self.usage = usage
        self.responseID = responseID
        self.requestID = requestID
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.output = try container.decode([ModelOutputItem].self, forKey: .output)
        self.usage = try container.decodeIfPresent(Usage.self, forKey: .usage) ?? Usage()
        self.responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
        self.requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        self.raw = try container.decodeIfPresent(JSONValue.self, forKey: .raw)
    }

    public var outputText: String {
        output.compactMap { item in
            if case .message(let message) = item {
                return message.content
            }
            return nil
        }.joined(separator: "\n")
    }

    public var functionCalls: [FunctionCall] {
        output.compactMap { item in
            if case .functionCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var customToolCalls: [CustomToolCall] {
        output.compactMap { item in
            if case .customToolCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var localShellCalls: [LocalShellCall] {
        output.compactMap { item in
            if case .localShellCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var computerCalls: [ComputerCall] {
        output.compactMap { item in
            if case .computerCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var shellCalls: [ShellCall] {
        output.compactMap { item in
            if case .shellCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var applyPatchCalls: [ApplyPatchCall] {
        output.compactMap { item in
            if case .applyPatchCall(let call) = item {
                return call
            }
            return nil
        }
    }

    public var refusal: String? {
        let refusal = output.compactMap { item in
            if case .refusal(let refusal) = item {
                return refusal
            }
            return nil
        }.joined()
        return refusal.isEmpty ? nil : refusal
    }

    public func toInputItems(reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil) -> [ModelInputItem] {
        output.map { $0.inputItem(reasoningItemIDPolicy: reasoningItemIDPolicy) }
    }

    private enum CodingKeys: String, CodingKey {
        case output
        case usage
        case responseID = "response_id"
        case requestID = "request_id"
        case raw
    }
}

public extension ModelOutputItem {
    var inputItem: ModelInputItem {
        inputItem(reasoningItemIDPolicy: nil)
    }

    func inputItem(reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil) -> ModelInputItem {
        switch self {
        case .message(let message):
            return .message(message)
        case .functionCall(let call):
            return .functionCall(call)
        case .customToolCall(let call):
            return .customToolCall(call)
        case .computerCall(let call):
            return .computerCall(call)
        case .localShellCall(let call):
            return .localShellCall(call)
        case .shellCall(let call):
            return .shellCall(call)
        case .applyPatchCall(let call):
            return .applyPatchCall(call)
        case .refusal(let refusal):
            return .refusal(refusal)
        case .reasoning(let value):
            return .reasoning(Self.reasoningValue(value, policy: reasoningItemIDPolicy))
        case .raw(let value):
            return .raw(value)
        }
    }

    private static func reasoningValue(
        _ value: JSONValue,
        policy: ReasoningItemIDPolicy?
    ) -> JSONValue {
        guard policy == .omit,
              case .object(var object) = value,
              object["type"]?.stringValue == "reasoning"
        else {
            return value
        }
        object.removeValue(forKey: "id")
        return .object(object)
    }
}

public enum ItemHelpers {
    public static let toolCallSessionDescriptionKey = "_agents_tool_description"
    public static let toolCallSessionTitleKey = "_agents_tool_title"

    public static func inputToNewInputList(_ input: String) -> [ModelInputItem] {
        [.message(AgentMessage(role: .user, content: input))]
    }

    public static func inputToNewInputList(_ input: [ModelInputItem]) -> [ModelInputItem] {
        input
    }

    public static func copyInputItems(_ input: [ModelInputItem]) -> [ModelInputItem] {
        input
    }

    public static func runItemToInputItem<Context: Sendable>(
        _ runItem: RunItem<Context>,
        reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil
    ) -> ModelInputItem? {
        guard let inputItem = runItem.toInputItem() else {
            return nil
        }
        guard reasoningItemIDPolicy == .omit,
              case .reasoning(let value) = inputItem
        else {
            return inputItem
        }
        return .reasoning(reasoningValue(value, policy: reasoningItemIDPolicy))
    }

    public static func runItemsToInputItems<Context: Sendable>(
        _ runItems: [RunItem<Context>],
        reasoningItemIDPolicy: ReasoningItemIDPolicy? = nil
    ) -> [ModelInputItem] {
        runItems.compactMap { runItemToInputItem($0, reasoningItemIDPolicy: reasoningItemIDPolicy) }
    }

    public static func normalizeInputItemsForModel(_ items: [ModelInputItem]) -> [ModelInputItem] {
        items.map(stripInternalInputItemMetadata)
    }

    public static func prepareModelInputItems(
        callerItems: [ModelInputItem],
        generatedItems: [ModelInputItem] = []
    ) -> [ModelInputItem] {
        let normalizedCallerItems = normalizeInputItemsForModel(callerItems)
        guard !generatedItems.isEmpty else {
            return normalizedCallerItems
        }
        let normalizedGeneratedItems = normalizeInputItemsForModel(generatedItems)
        return normalizedCallerItems + dropOrphanToolCalls(normalizedGeneratedItems)
    }

    public static func normalizeResumedInput(_ input: [ModelInputItem]) -> [ModelInputItem] {
        dropOrphanToolCalls(normalizeInputItemsForModel(input))
    }

    public static func dropOrphanToolCalls(
        _ items: [ModelInputItem],
        pruningIndexes: Set<Int>? = nil
    ) -> [ModelInputItem] {
        let completedCallIDs = completedCallIDsByOutputType(items)
        var droppedIndexes = Set<Int>()
        var filtered: [ModelInputItem] = []

        for (index, item) in items.enumerated() {
            guard let outputType = toolCallOutputType(for: item) else {
                filtered.append(item)
                continue
            }
            if let pruningIndexes, !pruningIndexes.contains(index) {
                filtered.append(item)
                continue
            }
            guard let callID = callID(for: item),
                  completedCallIDs[outputType, default: []].contains(callID)
            else {
                droppedIndexes.insert(index)
                continue
            }
            filtered.append(item)
        }

        guard !droppedIndexes.isEmpty else {
            return filtered
        }
        return dropReasoningItemsPrecedingDroppedCalls(items, droppedIndexes: droppedIndexes)
    }

    public static func fingerprintInputItem(
        _ item: ModelInputItem,
        ignoreIDsForMatching: Bool = false
    ) -> String? {
        var value = jsonValue(for: stripInternalInputItemMetadata(item))
        if ignoreIDsForMatching,
           case .object(var object) = value {
            object.removeValue(forKey: "id")
            value = .object(object)
        }
        return value.prettyPrinted()
    }

    public static func deduplicateInputItems(_ items: [ModelInputItem]) -> [ModelInputItem] {
        var seen = Set<String>()
        var deduplicated: [ModelInputItem] = []
        for item in items {
            guard let key = dedupeKey(for: item) else {
                deduplicated.append(item)
                continue
            }
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            deduplicated.append(item)
        }
        return deduplicated
    }

    public static func deduplicateInputItemsPreferringLatest(_ items: [ModelInputItem]) -> [ModelInputItem] {
        Array(deduplicateInputItems(Array(items.reversed())).reversed())
    }

    public static func stripInternalInputItemMetadata(_ item: ModelInputItem) -> ModelInputItem {
        switch item {
        case .raw(.object(var object)):
            object.removeValue(forKey: toolCallSessionDescriptionKey)
            object.removeValue(forKey: toolCallSessionTitleKey)
            return .raw(.object(object))
        case .reasoning(.object(var object)):
            object.removeValue(forKey: toolCallSessionDescriptionKey)
            object.removeValue(forKey: toolCallSessionTitleKey)
            return .reasoning(.object(object))
        default:
            return item
        }
    }

    public static func extractLastContent(_ item: ModelOutputItem) -> String {
        switch item {
        case .message(let message):
            return message.content
        case .refusal(let refusal):
            return refusal
        default:
            return ""
        }
    }

    public static func extractLastText(_ item: ModelOutputItem) -> String? {
        guard case .message(let message) = item, !message.content.isEmpty else {
            return nil
        }
        return message.content
    }

    public static func extractText(_ item: ModelOutputItem) -> String? {
        guard case .message(let message) = item, !message.content.isEmpty else {
            return nil
        }
        return message.content
    }

    public static func extractRefusal(_ item: ModelOutputItem) -> String? {
        guard case .refusal(let refusal) = item, !refusal.isEmpty else {
            return nil
        }
        return refusal
    }

    public static func textMessageOutput(_ item: ModelInputItem) -> String {
        guard case .message(let message) = item, message.role == .assistant else {
            return ""
        }
        return message.content
    }

    public static func textMessageOutputs(_ items: [ModelInputItem]) -> String {
        items.map(textMessageOutput).joined()
    }

    public static func toolCallOutputItem(toolCall: FunctionCall, output: ToolOutput) -> FunctionCallOutput {
        FunctionCallOutput(callID: toolCall.callID, output: output.modelValue, toolOrigin: toolCall.toolOrigin)
    }

    public static func toolCallOutputItem(toolCall: FunctionCall, output: String) -> FunctionCallOutput {
        FunctionCallOutput(callID: toolCall.callID, output: .string(output), toolOrigin: toolCall.toolOrigin)
    }

    private static func reasoningValue(_ value: JSONValue, policy: ReasoningItemIDPolicy?) -> JSONValue {
        guard policy == .omit,
              case .object(var object) = value,
              object["type"]?.stringValue == "reasoning"
        else {
            return value
        }
        object.removeValue(forKey: "id")
        return .object(object)
    }

    private static func completedCallIDsByOutputType(_ items: [ModelInputItem]) -> [String: Set<String>] {
        var completed: [String: Set<String>] = [:]
        for item in items {
            guard let type = itemType(for: item),
                  isToolCallOutputType(type),
                  let callID = callID(for: item)
            else {
                continue
            }
            completed[type, default: []].insert(callID)
        }
        return completed
    }

    private static func dropReasoningItemsPrecedingDroppedCalls(
        _ items: [ModelInputItem],
        droppedIndexes: Set<Int>
    ) -> [ModelInputItem] {
        guard !items.isEmpty else {
            return items
        }
        var dropReasoning = Set<Int>()
        for index in stride(from: items.count - 1, through: 0, by: -1) {
            guard isReasoningItem(items[index]),
                  !droppedIndexes.contains(index)
            else {
                continue
            }
            for nextIndex in (index + 1)..<items.count {
                if dropReasoning.contains(nextIndex) {
                    continue
                }
                if isReasoningItem(items[nextIndex]) {
                    continue
                }
                if droppedIndexes.contains(nextIndex) {
                    dropReasoning.insert(index)
                }
                break
            }
        }
        let excluded = droppedIndexes.union(dropReasoning)
        return items.enumerated().compactMap { index, item in
            excluded.contains(index) ? nil : item
        }
    }

    private static func isReasoningItem(_ item: ModelInputItem) -> Bool {
        switch item {
        case .reasoning:
            return true
        case .raw(let value):
            return value["type"]?.stringValue == "reasoning"
        default:
            return false
        }
    }

    private static func toolCallOutputType(for item: ModelInputItem) -> String? {
        switch item {
        case .functionCall:
            return "function_call_output"
        case .customToolCall:
            return "custom_tool_call_output"
        case .shellCall:
            return "shell_call_output"
        case .applyPatchCall:
            return "apply_patch_call_output"
        case .computerCall:
            return "computer_call_output"
        case .localShellCall:
            return "local_shell_call_output"
        case .raw(let value):
            guard let type = value["type"]?.stringValue else {
                return nil
            }
            return [
                "function_call": "function_call_output",
                "custom_tool_call": "custom_tool_call_output",
                "shell_call": "shell_call_output",
                "apply_patch_call": "apply_patch_call_output",
                "computer_call": "computer_call_output",
                "local_shell_call": "local_shell_call_output"
            ][type]
        default:
            return nil
        }
    }

    private static func isToolCallOutputType(_ type: String) -> Bool {
        [
            "function_call_output",
            "custom_tool_call_output",
            "shell_call_output",
            "apply_patch_call_output",
            "computer_call_output",
            "local_shell_call_output"
        ].contains(type)
    }

    private static func dedupeKey(for item: ModelInputItem) -> String? {
        let value = jsonValue(for: stripInternalInputItemMetadata(item))
        guard case .object(let object) = value else {
            return nil
        }
        let role = object["role"]?.stringValue
        let type = object["type"]?.stringValue ?? role
        if role != nil || type == "message" {
            return nil
        }
        if let type, let id = object["id"]?.stringValue, id != "__fake_id__" {
            return "id:\(type):\(id)"
        }
        if let type, let callID = object["call_id"]?.stringValue {
            return "call_id:\(type):\(callID)"
        }
        return nil
    }

    private static func itemType(for item: ModelInputItem) -> String? {
        switch item {
        case .message:
            return "message"
        case .functionCall:
            return "function_call"
        case .functionCallOutput:
            return "function_call_output"
        case .customToolCall:
            return "custom_tool_call"
        case .customToolCallOutput:
            return "custom_tool_call_output"
        case .computerCall:
            return "computer_call"
        case .computerCallOutput:
            return "computer_call_output"
        case .localShellCall:
            return "local_shell_call"
        case .localShellCallOutput:
            return "local_shell_call_output"
        case .shellCall:
            return "shell_call"
        case .shellCallOutput:
            return "shell_call_output"
        case .applyPatchCall:
            return "apply_patch_call"
        case .applyPatchCallOutput:
            return "apply_patch_call_output"
        case .refusal:
            return "refusal"
        case .reasoning(let value), .raw(let value):
            return value["type"]?.stringValue
        }
    }

    private static func callID(for item: ModelInputItem) -> String? {
        switch item {
        case .functionCall(let call):
            return call.callID
        case .functionCallOutput(let output):
            return output.callID
        case .customToolCall(let call):
            return call.callID
        case .customToolCallOutput(let output):
            return output.callID
        case .computerCall(let call):
            return call.callID
        case .computerCallOutput(let output):
            return output.callID
        case .localShellCall(let call):
            return call.callID
        case .localShellCallOutput(let output):
            return output.callID
        case .shellCall(let call):
            return call.callID
        case .shellCallOutput(let output):
            return output.callID
        case .applyPatchCall(let call):
            return call.callID
        case .applyPatchCallOutput(let output):
            return output.callID
        case .raw(let value):
            return value["call_id"]?.stringValue
        default:
            return nil
        }
    }

    private static func jsonValue(for item: ModelInputItem) -> JSONValue {
        (try? JSONValue.encoded(item)) ?? .null
    }
}
