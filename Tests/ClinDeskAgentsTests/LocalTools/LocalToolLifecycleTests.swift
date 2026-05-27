import Testing
import ClinDeskAgents

@Suite
struct LocalToolLifecycleTests {
    @Test
    func localShellToolInvokesRunAndAgentToolHooks() async throws {
        let events = LocalToolLifecycleLog()
        let shellCall = LocalShellCall(
            callID: "call_shell",
            action: [
                "type": "exec",
                "command": ["pwd"]
            ]
        )
        let model = FakeModel([
            ModelResponse(output: [.localShellCall(shellCall)]),
            ModelResponse(output: [.message(AgentMessage(role: .assistant, content: "done"))])
        ])
        let tool = LocalShellTool<Void> { _ in "shell output" }
        let agent = Agent<Void>(
            name: "shell-agent",
            tools: [.localShell(tool)],
            model: model,
            hooks: AgentHooks(
                onToolStart: { context, _, tool in
                    await events.append("agent:start:\(tool.name):\(context.toolCallID ?? "")")
                },
                onToolEnd: { _, _, tool, output in
                    await events.append("agent:end:\(tool.name):\(output)")
                }
            )
        )
        let hooks = RunHooks<Void>(
            onToolStart: { context, _, tool in
                await events.append("run:start:\(tool.name):\(context.toolCallID ?? "")")
            },
            onToolEnd: { _, _, tool, output in
                await events.append("run:end:\(tool.name):\(output)")
            }
        )

        let result = try await Runner.run(
            agent: agent,
            input: "run shell",
            runConfig: RunConfig(hooks: hooks)
        )

        #expect(result.finalOutput == "done")
        #expect(await events.all() == [
            "run:start:local_shell:call_shell",
            "agent:start:local_shell:call_shell",
            "run:end:local_shell:shell output",
            "agent:end:local_shell:shell output"
        ])
    }

    @Test
    func computerToolInvokesRunAndAgentToolHooks() async throws {
        let events = LocalToolLifecycleLog()
        let computer = RecordingComputer()
        let computerCall = ComputerCall(
            callID: "call_computer",
            action: ComputerAction(type: "screenshot")
        )
        let model = FakeModel([
            ModelResponse(output: [.computerCall(computerCall)]),
            ModelResponse(output: [.message(AgentMessage(role: .assistant, content: "done"))])
        ])
        let tool = ComputerTool<Void>(computer: computer)
        let agent = Agent<Void>(
            name: "computer-agent",
            tools: [.computer(tool)],
            model: model,
            hooks: AgentHooks(
                onToolStart: { context, _, tool in
                    await events.append("agent:start:\(tool.name):\(context.toolCallID ?? "")")
                },
                onToolEnd: { _, _, tool, output in
                    await events.append("agent:end:\(tool.name):\(output)")
                }
            )
        )
        let hooks = RunHooks<Void>(
            onToolStart: { context, _, tool in
                await events.append("run:start:\(tool.name):\(context.toolCallID ?? "")")
            },
            onToolEnd: { _, _, tool, output in
                await events.append("run:end:\(tool.name):\(output)")
            }
        )

        let result = try await Runner.run(
            agent: agent,
            input: "capture",
            runConfig: RunConfig(hooks: hooks)
        )

        #expect(result.finalOutput == "done")
        #expect(await events.all() == [
            "run:start:computer_use_preview:call_computer",
            "agent:start:computer_use_preview:call_computer",
            "run:end:computer_use_preview:data:image/png;base64,image-data",
            "agent:end:computer_use_preview:data:image/png;base64,image-data"
        ])
    }
}

private actor LocalToolLifecycleLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func all() -> [String] {
        events
    }
}
