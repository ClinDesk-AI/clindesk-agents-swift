import Foundation

public let runStateCurrentSchemaVersion = "1.11"

public protocol AnyRunState: Sendable {
    var interruptions: [ToolApprovalItem] { get }
}

public struct RunState<Context: Sendable>: AnyRunState, Sendable {
    public var startingAgent: Agent<Context>
    public var currentAgent: Agent<Context>
    public var originalInput: [ModelInputItem]
    public var sessionInputItems: [ModelInputItem]
    public var modelInput: [ModelInputItem]
    public var newItems: [ModelInputItem]
    public var modelResponses: [ModelResponse]
    public var runContext: RunContext<Context>
    public var trace: Trace
    public var lastResponseID: String?
    public var currentTurn: Int
    public var maxTurns: Int?
    public var interruptions: [ToolApprovalItem]
    public var pendingFunctionCalls: [FunctionCall]
    public var pendingCustomToolCalls: [CustomToolCall]
    public var pendingShellCalls: [ShellCall]
    public var pendingApplyPatchCalls: [ApplyPatchCall]
    public var inputGuardrailResults: [InputGuardrailResult]
    public var toolInputGuardrailResults: [ToolInputGuardrailResult]
    public var toolOutputGuardrailResults: [ToolOutputGuardrailResult]
    public var toolUseTrackerSnapshot: [String: [String]]
    public var generatedPromptCacheKey: String?
    public var config: RunConfig<Context>
    public var modelProvider: (any ModelProvider)?

    public init(
        startingAgent: Agent<Context>,
        currentAgent: Agent<Context>,
        originalInput: [ModelInputItem],
        sessionInputItems: [ModelInputItem]? = nil,
        modelInput: [ModelInputItem],
        newItems: [ModelInputItem],
        modelResponses: [ModelResponse],
        runContext: RunContext<Context>,
        trace: Trace,
        lastResponseID: String?,
        currentTurn: Int,
        maxTurns: Int?,
        interruptions: [ToolApprovalItem],
        pendingFunctionCalls: [FunctionCall],
        pendingCustomToolCalls: [CustomToolCall] = [],
        pendingShellCalls: [ShellCall] = [],
        pendingApplyPatchCalls: [ApplyPatchCall] = [],
        inputGuardrailResults: [InputGuardrailResult],
        toolInputGuardrailResults: [ToolInputGuardrailResult],
        toolOutputGuardrailResults: [ToolOutputGuardrailResult],
        toolUseTrackerSnapshot: [String: [String]],
        generatedPromptCacheKey: String? = nil,
        config: RunConfig<Context>,
        modelProvider: (any ModelProvider)?
    ) {
        self.startingAgent = startingAgent
        self.currentAgent = currentAgent
        self.originalInput = originalInput
        self.sessionInputItems = sessionInputItems ?? originalInput
        self.modelInput = modelInput
        self.newItems = newItems
        self.modelResponses = modelResponses
        self.runContext = runContext
        self.trace = trace
        self.lastResponseID = lastResponseID
        self.currentTurn = currentTurn
        self.maxTurns = maxTurns
        self.interruptions = interruptions
        self.pendingFunctionCalls = pendingFunctionCalls
        self.pendingCustomToolCalls = pendingCustomToolCalls
        self.pendingShellCalls = pendingShellCalls
        self.pendingApplyPatchCalls = pendingApplyPatchCalls
        self.inputGuardrailResults = inputGuardrailResults
        self.toolInputGuardrailResults = toolInputGuardrailResults
        self.toolOutputGuardrailResults = toolOutputGuardrailResults
        self.toolUseTrackerSnapshot = toolUseTrackerSnapshot
        self.generatedPromptCacheKey = generatedPromptCacheKey
        self.config = config
        self.modelProvider = modelProvider
    }

    public func getInterruptions() -> [ToolApprovalItem] {
        interruptions
    }

    public mutating func approve(_ item: ToolApprovalItem, alwaysApprove: Bool = false) {
        runContext.approveTool(item, alwaysApprove: alwaysApprove)
    }

    public mutating func reject(
        _ item: ToolApprovalItem,
        alwaysReject: Bool = false,
        rejectionMessage: String? = nil
    ) {
        runContext.rejectTool(item, alwaysReject: alwaysReject, rejectionMessage: rejectionMessage)
    }

    public func toJSON(context contextPayload: JSONValue? = nil) throws -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "$schemaVersion": .string(runStateCurrentSchemaVersion),
            "current_turn": .number(Double(currentTurn)),
            "current_agent": .object(agentReference(currentAgent)),
            "original_input": try JSONValue.encoded(originalInput),
            "session_input_items": try JSONValue.encoded(sessionInputItems),
            "model_input": try JSONValue.encoded(modelInput),
            "generated_items": try JSONValue.encoded(newItems),
            "session_items": try JSONValue.encoded(newItems),
            "model_responses": try JSONValue.encoded(modelResponses),
            "context": try contextJSON(contextPayload: contextPayload),
            "tool_use_tracker": try JSONValue.encoded(toolUseTrackerSnapshot),
            "max_turns": maxTurns.map { .number(Double($0)) } ?? .null,
            "no_active_agent_run": .bool(true),
            "input_guardrail_results": .array(inputGuardrailResults.map(serializeInputGuardrailResult)),
            "output_guardrail_results": .array([]),
            "tool_input_guardrail_results": .array(toolInputGuardrailResults.map(serializeToolInputGuardrailResult)),
            "tool_output_guardrail_results": .array(toolOutputGuardrailResults.map(serializeToolOutputGuardrailResult)),
            "conversation_id": .null,
            "previous_response_id": lastResponseID.map(JSONValue.string) ?? .null,
            "auto_previous_response_id": .bool(false),
            "generated_prompt_cache_key": generatedPromptCacheKey.map(JSONValue.string) ?? .null,
            "reasoning_item_id_policy": .null,
            "current_step": currentStepJSON(),
            "last_model_response": try modelResponses.last.map { try JSONValue.encoded($0) } ?? .null,
            "last_processed_response": lastProcessedResponseJSON(),
            "current_turn_persisted_item_count": .number(0)
        ]
        if let traceState = TraceState.fromTrace(trace),
           let traceJSON = traceState.toJSON() {
            payload["trace"] = .object(traceJSON)
        } else {
            payload["trace"] = .null
        }
        return payload
    }

    public func toString(context contextPayload: JSONValue? = nil, prettyPrinted: Bool = false) throws -> String {
        let json = try toJSON(context: contextPayload)
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(JSONValue.object(json))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func fromJSON(
        _ payload: [String: JSONValue],
        startingAgent: Agent<Context>,
        currentAgent: Agent<Context>? = nil,
        context: Context? = nil,
        config: RunConfig<Context> = RunConfig(),
        modelProvider: (any ModelProvider)? = nil
    ) throws -> RunState<Context> {
        let schemaVersion = payload["$schemaVersion"]?.stringValue
        guard schemaVersion == nil || schemaVersion == runStateCurrentSchemaVersion else {
            throw AgentsError.invalidRunConfig(
                "Unsupported RunState schema version '\(schemaVersion ?? "")'."
            )
        }

        let contextPayload = payload["context"]?.objectValue
        let runContext = try RunContext(
            context: context,
            usage: decodeJSON(
                Usage.self,
                from: contextPayload?["usage"],
                default: Usage()
            ),
            approvals: decodeApprovals(contextPayload?["approvals"])
        )
        let trace = traceFromJSON(payload["trace"])
        let lastProcessed = payload["last_processed_response"]?.objectValue

        return RunState(
            startingAgent: startingAgent,
            currentAgent: currentAgent ?? startingAgent,
            originalInput: try decodeJSON(
                [ModelInputItem].self,
                from: payload["original_input"],
                default: []
            ),
            sessionInputItems: try decodeJSON(
                [ModelInputItem].self,
                from: payload["session_input_items"],
                default: try decodeJSON(
                    [ModelInputItem].self,
                    from: payload["original_input"],
                    default: []
                )
            ),
            modelInput: try decodeJSON(
                [ModelInputItem].self,
                from: payload["model_input"],
                default: []
            ),
            newItems: try decodeJSON(
                [ModelInputItem].self,
                from: payload["generated_items"],
                default: []
            ),
            modelResponses: try decodeJSON(
                [ModelResponse].self,
                from: payload["model_responses"],
                default: []
            ),
            runContext: runContext,
            trace: trace,
            lastResponseID: payload["previous_response_id"]?.stringValue,
            currentTurn: payload["current_turn"]?.intValue ?? 0,
            maxTurns: payload["max_turns"]?.intValue,
            interruptions: decodeInterruptions(payload["current_step"]),
            pendingFunctionCalls: try decodeJSON(
                [FunctionCall].self,
                from: lastProcessed?["functions"],
                default: []
            ),
            pendingCustomToolCalls: try decodeJSON(
                [CustomToolCall].self,
                from: lastProcessed?["custom_tools"],
                default: []
            ),
            pendingShellCalls: try decodeJSON(
                [ShellCall].self,
                from: lastProcessed?["shell_tools"],
                default: []
            ),
            pendingApplyPatchCalls: try decodeJSON(
                [ApplyPatchCall].self,
                from: lastProcessed?["apply_patch_tools"],
                default: []
            ),
            inputGuardrailResults: decodeInputGuardrailResults(payload["input_guardrail_results"]),
            toolInputGuardrailResults: decodeToolInputGuardrailResults(payload["tool_input_guardrail_results"]),
            toolOutputGuardrailResults: decodeToolOutputGuardrailResults(payload["tool_output_guardrail_results"]),
            toolUseTrackerSnapshot: try decodeJSON(
                [String: [String]].self,
                from: payload["tool_use_tracker"],
                default: [:]
            ),
            generatedPromptCacheKey: payload["generated_prompt_cache_key"]?.stringValue,
            config: config,
            modelProvider: modelProvider
        )
    }

    public static func fromString(
        _ string: String,
        startingAgent: Agent<Context>,
        currentAgent: Agent<Context>? = nil,
        context: Context? = nil,
        config: RunConfig<Context> = RunConfig(),
        modelProvider: (any ModelProvider)? = nil
    ) throws -> RunState<Context> {
        guard let data = string.data(using: .utf8) else {
            throw AgentsError.invalidRunConfig("RunState string is not valid UTF-8.")
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let payload) = value else {
            throw AgentsError.invalidRunConfig("RunState string must decode to a JSON object.")
        }
        return try fromJSON(
            payload,
            startingAgent: startingAgent,
            currentAgent: currentAgent,
            context: context,
            config: config,
            modelProvider: modelProvider
        )
    }

    private func contextJSON(contextPayload: JSONValue?) throws -> JSONValue {
        .object([
            "usage": try JSONValue.encoded(runContext.usage),
            "approvals": .object(serializeApprovals(runContext.approvals)),
            "context": contextPayload ?? .null,
            "context_meta": .object([
                "type": .string(contextPayload == nil ? "none" : "json"),
                "serialized_via": .string(contextPayload == nil ? "none" : "caller"),
                "requires_deserializer": .bool(contextPayload != nil),
                "omitted": .bool(contextPayload == nil)
            ])
        ])
    }

    private func currentStepJSON() -> JSONValue {
        guard !interruptions.isEmpty else {
            return .null
        }
        return [
            "type": "next_step_interruption",
            "data": [
                "interruptions": .array(interruptions.map(serializeInterruption))
            ]
        ]
    }

    private func lastProcessedResponseJSON() -> JSONValue {
        guard !interruptions.isEmpty
            || !pendingFunctionCalls.isEmpty
            || !pendingCustomToolCalls.isEmpty
            || !pendingShellCalls.isEmpty
            || !pendingApplyPatchCalls.isEmpty
        else {
            return .null
        }
        return [
            "new_items": tryEncodedArray(newItems),
            "tools_used": .array([]),
            "functions": tryEncodedArray(pendingFunctionCalls),
            "custom_tools": tryEncodedArray(pendingCustomToolCalls),
            "shell_tools": tryEncodedArray(pendingShellCalls),
            "apply_patch_tools": tryEncodedArray(pendingApplyPatchCalls),
            "interruptions": .array(interruptions.map(serializeInterruption))
        ]
    }

    private func agentReference(_ agent: Agent<Context>) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "name": .string(agent.name)
        ]
        if let handoffDescription = agent.handoffDescription {
            payload["handoff_description"] = .string(handoffDescription)
        }
        if let modelName = agent.modelName {
            payload["model"] = .string(modelName)
        }
        return payload
    }
}

private func serializeApprovals(_ approvals: [String: ToolApprovalRecord]) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]
    for (toolName, record) in approvals {
        var recordPayload: [String: JSONValue] = [
            "approved": record.alwaysApproved
                ? .bool(true)
                : .array(record.approved.sorted().map(JSONValue.string)),
            "rejected": record.alwaysRejected
                ? .bool(true)
                : .array(record.rejected.sorted().map(JSONValue.string))
        ]
        if !record.rejectionMessages.isEmpty {
            recordPayload["rejection_messages"] = .object(record.rejectionMessages.mapValues(JSONValue.string))
        }
        if let stickyRejectionMessage = record.stickyRejectionMessage {
            recordPayload["sticky_rejection_message"] = .string(stickyRejectionMessage)
        }
        payload[toolName] = .object(recordPayload)
    }
    return payload
}

private func decodeApprovals(_ value: JSONValue?) -> [String: ToolApprovalRecord] {
    guard let object = value?.objectValue else {
        return [:]
    }
    return object.reduce(into: [String: ToolApprovalRecord]()) { result, element in
        guard let recordObject = element.value.objectValue else {
            return
        }
        let approvedValue = recordObject["approved"]
        let rejectedValue = recordObject["rejected"]
        result[element.key] = ToolApprovalRecord(
            approved: Set(approvedValue?.arrayValue?.compactMap(\.stringValue) ?? []),
            rejected: Set(rejectedValue?.arrayValue?.compactMap(\.stringValue) ?? []),
            alwaysApproved: approvedValue?.boolValue == true,
            alwaysRejected: rejectedValue?.boolValue == true,
            rejectionMessages: stringDictionary(recordObject["rejection_messages"]),
            stickyRejectionMessage: recordObject["sticky_rejection_message"]?.stringValue
        )
    }
}

private func serializeInterruption(_ item: ToolApprovalItem) -> JSONValue {
    var payload: [String: JSONValue] = [
        "tool_name": .string(item.toolName),
        "call_id": .string(item.callID),
        "arguments": item.arguments,
        "tool": serializeModelTool(item.tool),
        "allow_bare_name_alias": .bool(item.allowBareNameAlias)
    ]
    if let toolNamespace = item.toolNamespace {
        payload["tool_namespace"] = .string(toolNamespace)
    }
    if let toolLookupKey = item.toolLookupKey {
        payload["tool_lookup_key"] = .object(toolLookupKey.toDictionary())
    }
    if let toolOrigin = item.toolOrigin {
        payload["tool_origin"] = .object(toolOrigin.toDictionary())
    }
    return .object(payload)
}

private func decodeInterruptions(_ currentStep: JSONValue?) -> [ToolApprovalItem] {
    guard let step = currentStep?.objectValue,
          step["type"]?.stringValue == "next_step_interruption",
          let interruptions = step["data"]?["interruptions"]?.arrayValue
    else {
        return []
    }
    return interruptions.compactMap(decodeInterruption)
}

private func decodeInterruption(_ value: JSONValue) -> ToolApprovalItem? {
    guard let object = value.objectValue,
          let toolName = object["tool_name"]?.stringValue,
          let callID = object["call_id"]?.stringValue,
          let tool = decodeModelTool(object["tool"])
    else {
        return nil
    }
    return ToolApprovalItem(
        toolName: toolName,
        callID: callID,
        arguments: object["arguments"] ?? .emptyObject,
        tool: tool,
        toolNamespace: object["tool_namespace"]?.stringValue,
        allowBareNameAlias: object["allow_bare_name_alias"]?.boolValue ?? false,
        toolLookupKey: object["tool_lookup_key"]?.objectValue.flatMap(FunctionToolLookupKey.init(dictionary:)),
        toolOrigin: object["tool_origin"]?.objectValue.flatMap(ToolOrigin.init(dictionary:))
    )
}

private func serializeModelTool(_ tool: ModelTool) -> JSONValue {
    switch tool {
    case .function(let descriptor):
        return descriptorJSON(type: "function", value: descriptor)
    case .computer(let descriptor):
        return descriptorJSON(type: "computer", value: descriptor)
    case .localShell(let descriptor):
        return descriptorJSON(type: "local_shell", value: descriptor)
    case .shell(let descriptor):
        return descriptorJSON(type: "shell", value: descriptor)
    case .applyPatch(let descriptor):
        return descriptorJSON(type: "apply_patch", value: descriptor)
    case .custom(let descriptor):
        return descriptorJSON(type: "custom", value: descriptor)
    }
}

private func decodeModelTool(_ value: JSONValue?) -> ModelTool? {
    guard var object = value?.objectValue,
          let type = object.removeValue(forKey: "type")?.stringValue
    else {
        return nil
    }
    let descriptor = JSONValue.object(object)
    switch type {
    case "function":
        return try? .function(descriptor.decoded(ToolDescriptor.self))
    case "computer":
        return try? .computer(descriptor.decoded(ComputerToolDescriptor.self))
    case "local_shell":
        return try? .localShell(descriptor.decoded(LocalShellToolDescriptor.self))
    case "shell":
        return try? .shell(descriptor.decoded(ShellToolDescriptor.self))
    case "apply_patch":
        return try? .applyPatch(descriptor.decoded(ApplyPatchToolDescriptor.self))
    case "custom":
        return try? .custom(descriptor.decoded(CustomToolDescriptor.self))
    default:
        return nil
    }
}

private func descriptorJSON<T: Encodable>(type: String, value: T) -> JSONValue {
    var object = (try? JSONValue.encoded(value).objectValue) ?? [:]
    object["type"] = .string(type)
    return .object(object)
}

private func serializeInputGuardrailResult(_ result: InputGuardrailResult) -> JSONValue {
    [
        "guardrail_name": .string(result.guardrailName),
        "output": serializeGuardrailFunctionOutput(result.output)
    ]
}

private func decodeInputGuardrailResults(_ value: JSONValue?) -> [InputGuardrailResult] {
    value?.arrayValue?.compactMap { item in
        guard let object = item.objectValue,
              let name = object["guardrail_name"]?.stringValue
        else {
            return nil
        }
        return InputGuardrailResult(
            guardrailName: name,
            output: decodeGuardrailFunctionOutput(object["output"])
        )
    } ?? []
}

private func serializeToolInputGuardrailResult(_ result: ToolInputGuardrailResult) -> JSONValue {
    [
        "guardrail_name": .string(result.guardrailName),
        "tool_name": .string(result.toolName),
        "tool_call_id": .string(result.callID),
        "output": serializeToolGuardrailFunctionOutput(result.output)
    ]
}

private func decodeToolInputGuardrailResults(_ value: JSONValue?) -> [ToolInputGuardrailResult] {
    value?.arrayValue?.compactMap { item in
        guard let object = item.objectValue,
              let name = object["guardrail_name"]?.stringValue,
              let toolName = object["tool_name"]?.stringValue,
              let callID = object["tool_call_id"]?.stringValue
        else {
            return nil
        }
        return ToolInputGuardrailResult(
            guardrailName: name,
            toolName: toolName,
            callID: callID,
            output: decodeToolGuardrailFunctionOutput(object["output"])
        )
    } ?? []
}

private func serializeToolOutputGuardrailResult(_ result: ToolOutputGuardrailResult) -> JSONValue {
    [
        "guardrail_name": .string(result.guardrailName),
        "tool_name": .string(result.toolName),
        "tool_call_id": .string(result.callID),
        "output": serializeToolGuardrailFunctionOutput(result.output)
    ]
}

private func decodeToolOutputGuardrailResults(_ value: JSONValue?) -> [ToolOutputGuardrailResult] {
    value?.arrayValue?.compactMap { item in
        guard let object = item.objectValue,
              let name = object["guardrail_name"]?.stringValue,
              let toolName = object["tool_name"]?.stringValue,
              let callID = object["tool_call_id"]?.stringValue
        else {
            return nil
        }
        return ToolOutputGuardrailResult(
            guardrailName: name,
            toolName: toolName,
            callID: callID,
            output: decodeToolGuardrailFunctionOutput(object["output"])
        )
    } ?? []
}

private func serializeGuardrailFunctionOutput(_ output: GuardrailFunctionOutput) -> JSONValue {
    [
        "output_info": .string(output.outputInfo),
        "tripwire_triggered": .bool(output.tripwireTriggered)
    ]
}

private func decodeGuardrailFunctionOutput(_ value: JSONValue?) -> GuardrailFunctionOutput {
    let object = value?.objectValue
    return GuardrailFunctionOutput(
        outputInfo: object?["output_info"]?.stringValue ?? "",
        tripwireTriggered: object?["tripwire_triggered"]?.boolValue ?? false
    )
}

private func serializeToolGuardrailFunctionOutput(_ output: ToolGuardrailFunctionOutput) -> JSONValue {
    let behavior: String
    let message: String?
    switch output.behavior {
    case .allow:
        behavior = "allow"
        message = nil
    case .rejectContent(let value):
        behavior = "reject_content"
        message = value
    case .raiseException:
        behavior = "raise_exception"
        message = nil
    }
    return [
        "behavior": .string(behavior),
        "message": message.map(JSONValue.string) ?? .null,
        "output_info": .string(output.outputInfo)
    ]
}

private func decodeToolGuardrailFunctionOutput(_ value: JSONValue?) -> ToolGuardrailFunctionOutput {
    let object = value?.objectValue
    let outputInfo = object?["output_info"]?.stringValue ?? ""
    switch object?["behavior"]?.stringValue {
    case "reject_content":
        return .rejectContent(
            message: object?["message"]?.stringValue ?? "",
            outputInfo: outputInfo
        )
    case "raise_exception":
        return .raiseException(outputInfo: outputInfo)
    default:
        return .allow(outputInfo: outputInfo)
    }
}

private func tryEncodedArray<T: Encodable>(_ value: [T]) -> JSONValue {
    (try? JSONValue.encoded(value)) ?? .array([])
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from value: JSONValue?, default defaultValue: T) throws -> T {
    guard let value, value != .null else {
        return defaultValue
    }
    return try value.decoded(type)
}

private func traceFromJSON(_ value: JSONValue?) -> Trace {
    guard let object = value?.objectValue,
          let traceState = TraceState.fromJSON(object),
          let trace = reattachTrace(from: traceState)
    else {
        return .noOp()
    }
    return trace
}

private func stringDictionary(_ value: JSONValue?) -> [String: String] {
    value?.objectValue?.reduce(into: [String: String]()) { result, element in
        if let string = element.value.stringValue {
            result[element.key] = string
        }
    } ?? [:]
}
