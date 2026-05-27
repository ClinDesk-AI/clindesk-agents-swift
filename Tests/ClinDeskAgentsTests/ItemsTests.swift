import Testing
import Foundation
import ClinDeskAgents

@Suite
struct ItemsTests {
    @Test
    func modelResponseConvertsOutputToInputItems() {
        let call = FunctionCall(
            id: "fc_1",
            callID: "call_1",
            name: "lookup",
            namespace: "crm",
            arguments: ["id": "cus_123"]
        )
        let response = ModelResponse(output: [
            .message(AgentMessage(role: .assistant, content: "Hello.")),
            .functionCall(call),
            .refusal("No.")
        ])

        #expect(response.toInputItems() == [
            .message(AgentMessage(role: .assistant, content: "Hello.")),
            .functionCall(call),
            .refusal("No.")
        ])
    }

    @Test
    func modelResponseReasoningInputItemsCanOmitIDs() {
        let reasoning: JSONValue = [
            "type": "reasoning",
            "id": "rs_123",
            "summary": [
                ["type": "summary_text", "text": "Thinking"]
            ]
        ]
        let response = ModelResponse(output: [.reasoning(reasoning)])

        #expect(response.toInputItems() == [.reasoning(reasoning)])
        #expect(response.toInputItems(reasoningItemIDPolicy: .preserve) == [.reasoning(reasoning)])
        #expect(response.toInputItems(reasoningItemIDPolicy: .omit) == [
            .reasoning([
                "type": "reasoning",
                "summary": [
                    ["type": "summary_text", "text": "Thinking"]
                ]
            ])
        ])
    }

    @Test
    func modelResponseCodableUsesUpstreamResponseKeys() throws {
        let response = ModelResponse(
            output: [
                .message(AgentMessage(role: .assistant, content: "Hello."))
            ],
            usage: Usage(requests: 1, inputTokens: 2, outputTokens: 3, totalTokens: 5),
            responseID: "resp_123",
            requestID: "req_123",
            raw: ["provider": "local"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(response)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)

        #expect(json["response_id"]?.stringValue == "resp_123")
        #expect(json["request_id"]?.stringValue == "req_123")
        #expect(json["usage"]?["requests"] == .number(1))
        #expect(json["raw"]?["provider"] == .string("local"))
        if case .array(let outputItems)? = json["output"] {
            #expect(outputItems.first?["type"] == .string("message"))
            #expect(outputItems.first?["role"] == .string("assistant"))
        } else {
            Issue.record("Expected encoded model response output items.")
        }
        #expect(json["responseID"] == nil)
        #expect(json["requestID"] == nil)

        let decoded = try JSONDecoder().decode(ModelResponse.self, from: data)
        #expect(decoded == response)
    }

    @Test
    func modelResponseDecodesMissingUsageAndIdentifiers() throws {
        let data = #"{"output":[{"message":{"role":"assistant","content":"Hello."}}]}"#
            .data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ModelResponse.self, from: data)

        #expect(decoded.output == [.message(AgentMessage(role: .assistant, content: "Hello."))])
        #expect(decoded.usage == Usage())
        #expect(decoded.responseID == nil)
        #expect(decoded.requestID == nil)
        #expect(decoded.raw == nil)
    }

    @Test
    func modelItemsCodableUseTypedSnakeCaseShape() throws {
        let item = ModelInputItem.functionCall(FunctionCall(
            id: "fc_123",
            callID: "call_123",
            name: "lookup",
            namespace: "crm",
            arguments: ["id": "acct_123"],
            toolOrigin: ToolOrigin(type: .function)
        ))

        let data = try JSONEncoder().encode(item)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)

        #expect(json["type"] == .string("function_call"))
        #expect(json["call_id"] == .string("call_123"))
        #expect(json["tool_origin"]?["type"] == .string("function"))
        #expect(json["callID"] == nil)
        #expect(json["toolOrigin"] == nil)
        #expect(try JSONDecoder().decode(ModelInputItem.self, from: data) == item)
        #expect(try JSONDecoder().decode(ModelOutputItem.self, from: data) == .functionCall(
            FunctionCall(
                id: "fc_123",
                callID: "call_123",
                name: "lookup",
                namespace: "crm",
                arguments: ["id": "acct_123"],
                toolOrigin: ToolOrigin(type: .function)
            )
        ))
    }

    @Test
    func itemHelpersMirrorUpstreamTextAndInputHelpers() {
        let input = ItemHelpers.inputToNewInputList("Hi")
        let items: [ModelInputItem] = [
            .message(AgentMessage(role: .user, content: "ignored")),
            .message(AgentMessage(role: .assistant, content: "foo")),
            .functionCallOutput(FunctionCallOutput(callID: "call_1", output: .string("ignored"))),
            .message(AgentMessage(role: .assistant, content: "bar"))
        ]

        #expect(input == [.message(AgentMessage(role: .user, content: "Hi"))])
        #expect(ItemHelpers.inputToNewInputList(items) == items)
        #expect(ItemHelpers.textMessageOutput(items[1]) == "foo")
        #expect(ItemHelpers.textMessageOutputs(items) == "foobar")
        #expect(ItemHelpers.extractLastContent(.message(AgentMessage(role: .assistant, content: "text"))) == "text")
        #expect(ItemHelpers.extractLastContent(.refusal("No.")) == "No.")
        #expect(ItemHelpers.extractLastContent(.functionCall(FunctionCall(name: "lookup", arguments: [:]))) == "")
        #expect(ItemHelpers.extractLastText(.message(AgentMessage(role: .assistant, content: "text"))) == "text")
        #expect(ItemHelpers.extractLastText(.refusal("No.")) == nil)
        #expect(ItemHelpers.extractLastText(.functionCall(FunctionCall(name: "lookup", arguments: [:]))) == nil)
        #expect(ItemHelpers.extractText(.message(AgentMessage(role: .assistant, content: "text"))) == "text")
        #expect(ItemHelpers.extractText(.functionCall(FunctionCall(name: "lookup", arguments: [:]))) == nil)
        #expect(ItemHelpers.extractRefusal(.refusal("No.")) == "No.")
        #expect(ItemHelpers.extractRefusal(.message(AgentMessage(role: .assistant, content: "text"))) == nil)
    }

    @Test
    func itemHelpersBuildToolCallOutputItems() {
        let call = FunctionCall(
            callID: "call_lookup",
            name: "lookup",
            arguments: ["query": "hours"]
        )
        let structured = ToolOutput.structured([
            .text("Done."),
            .image(ToolOutputImage(fileID: "file_123", detail: .high))
        ])

        #expect(ItemHelpers.toolCallOutputItem(toolCall: call, output: "plain") == FunctionCallOutput(
            callID: "call_lookup",
            output: .string("plain")
        ))
        #expect(ItemHelpers.toolCallOutputItem(toolCall: call, output: structured) == FunctionCallOutput(
            callID: "call_lookup",
            output: [
                ["type": "input_text", "text": "Done."],
                ["type": "input_image", "file_id": "file_123", "detail": "high"]
            ]
        ))
    }

    @Test
    func itemHelpersPrepareModelInputByPruningGeneratedOrphanToolCalls() {
        let callerCall = FunctionCall(
            id: "fc_user",
            callID: "call_user_supplied",
            name: "lookup",
            arguments: [:]
        )
        let orphanCall = FunctionCall(
            id: "fc_orphan",
            callID: "call_orphan",
            name: "lookup",
            arguments: [:]
        )
        let matchedCall = FunctionCall(
            id: "fc_matched",
            callID: "call_matched",
            name: "lookup",
            arguments: [:]
        )
        let matchedOutput = FunctionCallOutput(callID: "call_matched", output: .string("ok"))
        let callerItems: [ModelInputItem] = [
            .functionCall(callerCall)
        ]
        let orphanReasoning: JSONValue = [
            "type": "reasoning",
            "id": "rs_orphan",
            "summary": [["type": "summary_text", "text": "will be dropped"]]
        ]
        let keptReasoning: JSONValue = [
            "type": "reasoning",
            "id": "rs_kept",
            "summary": [["type": "summary_text", "text": "will stay"]]
        ]
        let generatedItems: [ModelInputItem] = [
            .reasoning(orphanReasoning),
            .functionCall(orphanCall),
            .reasoning(keptReasoning),
            .functionCall(matchedCall),
            .functionCallOutput(matchedOutput)
        ]

        let prepared = ItemHelpers.prepareModelInputItems(
            callerItems: callerItems,
            generatedItems: generatedItems
        )

        #expect(prepared == [
            .functionCall(callerCall),
            .reasoning(keptReasoning),
            .functionCall(matchedCall),
            .functionCallOutput(matchedOutput)
        ])
    }

    @Test
    func itemHelpersDropRawReasoningBeforePrunedRawToolCalls() {
        let rawReasoning = ModelInputItem.raw([
            "type": "reasoning",
            "id": "rs_raw",
            "summary": [
                ["type": "summary_text", "text": "will be dropped"]
            ]
        ])
        let rawOrphanCall = ModelInputItem.raw([
            "type": "function_call",
            "id": "fc_raw_orphan",
            "call_id": "call_raw_orphan",
            "name": "lookup",
            "arguments": "{}"
        ])
        let keptMessage = ModelInputItem.message(AgentMessage(role: .assistant, content: "keep"))

        let prepared = ItemHelpers.prepareModelInputItems(
            callerItems: [],
            generatedItems: [
                rawReasoning,
                rawOrphanCall,
                keptMessage
            ]
        )

        #expect(prepared == [keptMessage])
    }

    @Test
    func itemHelpersDeduplicateByStableIdentifiers() {
        let first = ModelInputItem.functionCallOutput(FunctionCallOutput(
            callID: "call_lookup",
            output: .string("first")
        ))
        let second = ModelInputItem.functionCallOutput(FunctionCallOutput(
            callID: "call_lookup",
            output: .string("second")
        ))
        let message = ModelInputItem.message(AgentMessage(role: .assistant, content: "Keep messages."))
        let rawWithID = ModelInputItem.raw([
            "type": "reasoning",
            "id": "rs_123",
            "summary": []
        ])
        let rawWithSameID = ModelInputItem.raw([
            "type": "reasoning",
            "id": "rs_123",
            "summary": [["text": "new"]]
        ])

        #expect(ItemHelpers.deduplicateInputItems([first, second, message, rawWithID, rawWithSameID]) == [
            first,
            message,
            rawWithID
        ])
        #expect(ItemHelpers.deduplicateInputItemsPreferringLatest([first, second, message, rawWithID, rawWithSameID]) == [
            second,
            message,
            rawWithSameID
        ])
    }

    @Test
    func itemHelpersStripMetadataAndFingerprintModelItems() {
        let raw = ModelInputItem.raw([
            "type": "function_call",
            "id": "fc_123",
            "call_id": "call_lookup",
            "_agents_tool_description": "internal",
            "_agents_tool_title": "Lookup",
            "name": "lookup"
        ])

        #expect(ItemHelpers.normalizeInputItemsForModel([raw]) == [
            .raw([
                "type": "function_call",
                "id": "fc_123",
                "call_id": "call_lookup",
                "name": "lookup"
            ])
        ])
        #expect(ItemHelpers.fingerprintInputItem(raw) == #"{"call_id":"call_lookup","id":"fc_123","name":"lookup","type":"function_call"}"#)
        #expect(ItemHelpers.fingerprintInputItem(raw, ignoreIDsForMatching: true) == #"{"call_id":"call_lookup","name":"lookup","type":"function_call"}"#)
    }

    @Test
    func runItemsExposeUpstreamTypeNamesAndInputConversion() {
        let agent = Agent<Void>(name: "Assistant")
        let message = AgentMessage(role: .assistant, content: "Hello.")
        let call = FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:])
        let output = FunctionCallOutput(callID: "call_lookup", output: .string("Done."))

        let messageItem = RunItem.messageOutputItem(MessageOutputItem(agent: agent, rawItem: message))
        let toolCallItem = RunItem.toolCallItem(ToolCallItem(agent: agent, rawItem: call))
        let toolOutputItem = RunItem.toolCallOutputItem(ToolCallOutputItem(
            agent: agent,
            rawItem: output,
            output: output.output
        ))

        #expect(messageItem.type == "message_output_item")
        #expect(messageItem.toInputItem() == .message(message))
        #expect(toolCallItem.type == "tool_call_item")
        #expect(toolCallItem.toInputItem() == .functionCall(call))
        #expect(toolOutputItem.type == "tool_call_output_item")
        #expect(toolOutputItem.toInputItem() == .functionCallOutput(output))
    }
}
