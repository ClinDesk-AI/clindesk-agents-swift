import Testing
import ClinDeskAgents

@Suite
struct ToolOutputTrimmerTests {
    @Test
    func toolOutputTrimmerTrimsOldFunctionOutputsAndKeepsRecentTurns() async throws {
        let oldOutput = String(repeating: "a", count: 200)
        let recentOutput = String(repeating: "b", count: 200)
        let items: [ModelInputItem] = [
            .message(AgentMessage(role: .user, content: "old turn")),
            .functionCall(FunctionCall(callID: "call_search", name: "search", arguments: [:])),
            .functionCallOutput(FunctionCallOutput(callID: "call_search", output: .string(oldOutput))),
            .message(AgentMessage(role: .user, content: "recent turn")),
            .functionCall(FunctionCall(callID: "call_recent", name: "search", arguments: [:])),
            .functionCallOutput(FunctionCallOutput(callID: "call_recent", output: .string(recentOutput)))
        ]
        let trimmer = try ToolOutputTrimmer(
            recentTurns: 1,
            maxOutputChars: 50,
            previewChars: 12
        )
        let data = CallModelData(
            modelData: ModelInputData(input: items, instructions: "instructions"),
            agent: Agent<Void>(name: "Assistant"),
            context: nil
        )

        let filtered = try await trimmer.filter(data)

        #expect(filtered.instructions == "instructions")
        guard case .functionCallOutput(let oldTrimmed) = filtered.input[2] else {
            Issue.record("Expected old output item")
            return
        }
        #expect(oldTrimmed.output.stringValue?.contains("[Trimmed: search output") == true)
        #expect(oldTrimmed.output.stringValue?.contains("aaaaaaaaaaaa...") == true)
        #expect(filtered.input[5] == .functionCallOutput(FunctionCallOutput(
            callID: "call_recent",
            output: .string(recentOutput)
        )))
    }

    @Test
    func toolOutputTrimmerHonorsTrimmableToolNames() async throws {
        let output = String(repeating: "x", count: 200)
        let items: [ModelInputItem] = [
            .message(AgentMessage(role: .user, content: "old turn")),
            .functionCall(FunctionCall(
                callID: "call_lookup",
                name: "lookup",
                namespace: "crm",
                arguments: [:]
            )),
            .functionCallOutput(FunctionCallOutput(callID: "call_lookup", output: .string(output))),
            .functionCall(FunctionCall(callID: "call_other", name: "other", arguments: [:])),
            .functionCallOutput(FunctionCallOutput(callID: "call_other", output: .string(output))),
            .message(AgentMessage(role: .user, content: "recent turn"))
        ]
        let trimmer = try ToolOutputTrimmer(
            recentTurns: 1,
            maxOutputChars: 50,
            previewChars: 10,
            trimmableTools: ["crm.lookup"]
        )
        let data = CallModelData(
            modelData: ModelInputData(input: items, instructions: nil),
            agent: Agent<Void>(name: "Assistant"),
            context: nil
        )

        let filtered = try await trimmer(data)

        guard case .functionCallOutput(let lookupOutput) = filtered.input[2] else {
            Issue.record("Expected namespaced lookup output")
            return
        }
        #expect(lookupOutput.output.stringValue?.contains("[Trimmed: crm.lookup output") == true)
        #expect(filtered.input[4] == .functionCallOutput(FunctionCallOutput(
            callID: "call_other",
            output: .string(output)
        )))
    }

    @Test
    func toolOutputTrimmerCanRunAsCallModelInputFilter() async throws {
        let oldOutput = String(repeating: "z", count: 180)
        let input: [ModelInputItem] = [
            .message(AgentMessage(role: .user, content: "old turn")),
            .functionCall(FunctionCall(callID: "call_search", name: "search", arguments: [:])),
            .functionCallOutput(FunctionCallOutput(callID: "call_search", output: .string(oldOutput))),
            .message(AgentMessage(role: .user, content: "recent turn"))
        ]
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let trimmer = try ToolOutputTrimmer(
            recentTurns: 1,
            maxOutputChars: 50,
            previewChars: 8
        )
        let agent = Agent<Void>(name: "Assistant", model: model)

        _ = try await Runner.run(
            agent: agent,
            input: input,
            runConfig: RunConfig(callModelInputFilter: trimmer.filter)
        )

        let requests = await model.requests()
        guard case .functionCallOutput(let output)? = requests.first?.input[2] else {
            Issue.record("Expected filtered function output")
            return
        }
        #expect(output.output.stringValue?.contains("[Trimmed: search output") == true)
    }
}
