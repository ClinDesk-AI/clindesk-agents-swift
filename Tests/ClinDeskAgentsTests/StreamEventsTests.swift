import Testing
import ClinDeskAgents

@Suite
struct StreamEventsTests {
    @Test
    func runStreamEmitsUpstreamRunItemsForToolCallsAndOutputs() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_lookup",
                    name: "lookup",
                    arguments: ["query": "hours"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Open until 5."))
            ])
        ])
        let lookup = FunctionTool<Void>(name: "lookup", description: "Lookup facts.") { _, _ in
            .text("open")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [lookup], model: model)

        var runItems: [String] = []
        for try await event in Runner.runStream(agent: agent, input: "Hours?") {
            guard case .runItemStreamEvent(let event) = event else {
                continue
            }
            switch event.item {
            case .toolCallItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.name):\(item.callID)")
            case .toolCallOutputItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.callID):\(item.output.stringValue ?? "")")
            case .messageOutputItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.content)")
            default:
                continue
            }
        }

        #expect(runItems == [
            "tool_called:tool_call_item:lookup:call_lookup",
            "tool_output:tool_call_output_item:call_lookup:open",
            "message_output_created:message_output_item:Open until 5."
        ])
    }

    @Test
    func runStreamClassifiesHandoffCallsSeparatelyFromToolCalls() async throws {
        let triageModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_transfer",
                    name: "transfer_to_booking",
                    arguments: [:]
                ))
            ])
        ])
        let bookingModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Booking ready."))
            ])
        ])
        let booking = Agent<Void>(name: "Booking", model: bookingModel)
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: booking, toolName: "transfer_to_booking")],
            model: triageModel
        )

        var runItems: [String] = []
        for try await event in Runner.runStream(agent: triage, input: "Need booking") {
            guard case .runItemStreamEvent(let event) = event else {
                continue
            }
            switch event.item {
            case .handoffCallItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.name):\(item.rawItem.callID)")
            case .handoffOutputItem(let item):
                runItems.append(
                    "\(event.name.rawValue):\(item.type):\(item.sourceAgent.name):\(item.targetAgent.name):\(item.rawItem?.callID ?? "")"
                )
            case .messageOutputItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.content)")
            default:
                continue
            }
        }

        #expect(runItems == [
            "handoff_requested:handoff_call_item:transfer_to_booking:call_transfer",
            "handoff_occured:handoff_output_item:Triage:Booking:call_transfer",
            "message_output_created:message_output_item:Booking ready."
        ])
    }

    @Test
    func runStreamEmitsCustomToolOutputsAsToolOutputItems() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .customToolCall(CustomToolCall(
                    callID: "call_custom",
                    name: "raw_editor",
                    input: "hello"
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Edited."))
            ])
        ])
        let customTool = CustomTool<Void>(
            name: "raw_editor",
            description: "Edit raw text."
        ) { _, input in
            input.uppercased()
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.custom(customTool)],
            model: model
        )

        var runItems: [String] = []
        for try await event in Runner.runStream(agent: agent, input: "Run") {
            guard case .runItemStreamEvent(let event) = event else {
                continue
            }
            switch event.item {
            case .customToolCallItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.name):\(item.rawItem.callID)")
            case .customToolCallOutputItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.callID):\(item.output)")
            case .messageOutputItem(let item):
                runItems.append("\(event.name.rawValue):\(item.type):\(item.rawItem.content)")
            default:
                continue
            }
        }

        #expect(runItems == [
            "tool_called:tool_call_item:raw_editor:call_custom",
            "tool_output:tool_call_output_item:call_custom:HELLO",
            "message_output_created:message_output_item:Edited."
        ])
    }
}
