import Testing
import ClinDeskAgents

@Suite
struct AgentToolStreamTests {
    @Test
    func agentAsToolStreamsNestedRunEvents() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let streamEvents = StringRecorder()
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(onStream: { payload in
                    let callID = payload.toolCall?.callID ?? ""
                    switch payload.event {
                    case .agentUpdatedStreamEvent(let event):
                        await streamEvents.append("agentUpdated:\(payload.agent.name):\(event.newAgent.name):\(callID)")
                    case .modelResponseEvent(let event):
                        switch event.data {
                        case .started:
                            await streamEvents.append("rawStarted:\(payload.agent.name):\(callID)")
                        case .completed:
                            await streamEvents.append("rawCompleted:\(payload.agent.name):\(callID)")
                        default:
                            break
                        }
                    case .runItemStreamEvent(let event):
                        if case .messageOutputItem(let item) = event.item {
                            await streamEvents.append(
                                "messageOutput:\(payload.agent.name):\(item.rawItem.content):\(callID)"
                            )
                        }
                    }
                })
            ],
            model: parentModel
        )

        let result = try await Runner.run(agent: parent, input: "Run")

        #expect(result.finalOutput == "Parent done.")
        #expect(await streamEvents.all() == [
            "agentUpdated:Child:Child:call_child",
            "rawStarted:Child:call_child",
            "rawCompleted:Child:call_child",
            "messageOutput:Child:Child answer.:call_child"
        ])
    }

    @Test
    func agentAsToolStreamHandlerErrorsDoNotFailToolRun() async throws {
        let childModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Child answer."))
            ])
        ])
        let child = Agent<Void>(name: "Child", model: childModel)
        let parentModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_child",
                    name: "child",
                    arguments: ["input": "Need a child answer."]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Parent done."))
            ])
        ])
        let parent = Agent<Void>(
            name: "Parent",
            tools: [
                child.asTool(onStream: { _ in
                    throw AgentsError.invalidRunConfig("stream handler failed")
                })
            ],
            model: parentModel
        )

        let result = try await Runner.run(agent: parent, input: "Run")

        #expect(result.finalOutput == "Parent done.")
    }
}
