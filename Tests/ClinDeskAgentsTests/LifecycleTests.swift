import Testing
import ClinDeskAgents

@Suite
struct LifecycleTests {
    @Test
    func runAndAgentHooksReceiveLifecycleEvents() async throws {
        let events = LifecycleEventLog()
        let model = FakeModel([
            ModelResponse(
                output: [
                    .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
                ],
                usage: Usage(requests: 1, inputTokens: 8, outputTokens: 2, totalTokens: 10)
            ),
            ModelResponse(
                output: [
                    .message(AgentMessage(role: .assistant, content: "Done."))
                ],
                usage: Usage(requests: 1, inputTokens: 5, outputTokens: 3, totalTokens: 8)
            )
        ])
        let tool = FunctionTool<Void>(name: "lookup", description: "Lookup.") { _, _ in
            .text("tool ok")
        }
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Be helpful."),
            tools: [tool],
            model: model,
            hooks: AgentHooks(
                onStart: { context, agent in
                    await events.append("agent:start:\(agent.name):\(context.usage.totalTokens)")
                },
                onEnd: { _, agent, output in
                    await events.append("agent:end:\(agent.name):\(output)")
                },
                onToolStart: { context, agent, tool in
                    await events.append("agent:tool_start:\(agent.name):\(tool.name):\(context.toolCallID ?? "")")
                },
                onToolEnd: { _, agent, tool, output in
                    await events.append("agent:tool_end:\(agent.name):\(tool.name):\(output)")
                },
                onLLMStart: { _, agent, instructions, input in
                    await events.append("agent:llm_start:\(agent.name):\(instructions ?? ""):\(input.count)")
                },
                onLLMEnd: { context, agent, _ in
                    await events.append("agent:llm_end:\(agent.name):\(context.usage.totalTokens)")
                }
            )
        )
        let hooks = RunHooks<Void>(
            onLLMStart: { _, agent, _, input in
                await events.append("run:llm_start:\(agent.name):\(input.count)")
            },
            onLLMEnd: { context, agent, _ in
                await events.append("run:llm_end:\(agent.name):\(context.usage.totalTokens)")
            },
            onAgentStart: { context, agent in
                await events.append("run:start:\(agent.name):\(context.usage.totalTokens)")
            },
            onAgentEnd: { _, agent, output in
                await events.append("run:end:\(agent.name):\(output)")
            },
            onToolStart: { context, agent, tool in
                await events.append("run:tool_start:\(agent.name):\(tool.name):\(context.toolCallID ?? "")")
            },
            onToolEnd: { _, agent, tool, output in
                await events.append("run:tool_end:\(agent.name):\(tool.name):\(output)")
            }
        )

        let result = try await Runner.run(
            agent: agent,
            input: "Hi",
            runConfig: RunConfig(hooks: hooks)
        )

        let allEvents = await events.all()
        #expect(result.finalOutput == "Done.")
        #expect(allEvents.filter { $0 == "run:start:Assistant:0" }.count == 1)
        #expect(allEvents.filter { $0 == "agent:start:Assistant:0" }.count == 1)
        #expect(allEvents.contains("run:llm_end:Assistant:10"))
        #expect(allEvents.contains("agent:llm_end:Assistant:18"))
        #expect(allEvents.contains("run:tool_start:Assistant:lookup:call_lookup"))
        #expect(allEvents.contains("agent:tool_end:Assistant:lookup:tool ok"))
        #expect(allEvents.contains("run:end:Assistant:Done."))
        #expect(allEvents.contains("agent:end:Assistant:Done."))
    }

    @Test
    func handoffHooksReceiveSourceAndTargetAgents() async throws {
        let events = LifecycleEventLog()
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_handoff", name: "transfer_to_specialist", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Specialist done."))
            ])
        ])
        let specialist = Agent<Void>(
            name: "Specialist",
            model: model,
            hooks: AgentHooks(onStart: { _, agent in
                await events.append("specialist:start:\(agent.name)")
            })
        )
        let triage = Agent<Void>(
            name: "Triage",
            handoffs: [Handoff(to: specialist)],
            model: model,
            hooks: AgentHooks(onHandoff: { _, target, source in
                await events.append("triage:handoff:\(source.name)->\(target.name)")
            })
        )
        let hooks = RunHooks<Void>(
            onAgentStart: { _, agent in
                await events.append("run:start:\(agent.name)")
            },
            onHandoff: { _, source, target in
                await events.append("run:handoff:\(source.name)->\(target.name)")
            }
        )

        let result = try await Runner.run(
            agent: triage,
            input: "Route me",
            runConfig: RunConfig(hooks: hooks)
        )

        let allEvents = await events.all()
        #expect(result.finalOutput == "Specialist done.")
        #expect(allEvents.contains("run:start:Triage"))
        #expect(allEvents.contains("run:handoff:Triage->Specialist"))
        #expect(allEvents.contains("triage:handoff:Triage->Specialist"))
        #expect(allEvents.contains("specialist:start:Specialist"))
        #expect(allEvents.firstIndex(of: "run:handoff:Triage->Specialist")! <
            allEvents.firstIndex(of: "specialist:start:Specialist")!)
    }
}

private actor LifecycleEventLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func all() -> [String] {
        events
    }
}
