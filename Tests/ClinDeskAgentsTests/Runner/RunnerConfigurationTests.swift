import Foundation
import Testing
import ClinDeskAgents

@Suite
struct RunnerConfigurationTests {
    @Test
    func runConfigTraceIncludeSensitiveDataDefaultUsesLocalEnvironmentName() {
        #expect(RunConfigDefaults.traceIncludeSensitiveData(environment: [:]) == true)
        #expect(RunConfigDefaults.traceIncludeSensitiveData(environment: [
            "CLINDESK_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA": "yes"
        ]) == true)
        #expect(RunConfigDefaults.traceIncludeSensitiveData(environment: [
            "CLINDESK_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA": "0"
        ]) == false)
        #expect(RunConfigDefaults.traceIncludeSensitiveData(environment: [
            "CLINDESK_AGENTS_TRACE_INCLUDE_SENSITIVE_DATA": "off"
        ]) == false)
    }

    @Test
    func runConfigDefaultMaxTurnsMirrorsUpstreamConstant() {
        let config = RunConfig<Void>()

        #expect(RunConfigDefaults.defaultMaxTurns == 10)
        #expect(config.maxTurns == RunConfigDefaults.defaultMaxTurns)
    }

    @Test
    func toolNotFoundBehaviorUsesUpstreamRawValues() throws {
        let config = RunConfig<Void>()

        #expect(config.toolNotFoundBehavior == .raiseError)
        #expect(ToolNotFoundBehavior.raiseError.rawValue == "raise_error")
        #expect(ToolNotFoundBehavior.returnErrorToModel.rawValue == "return_error_to_model")

        let encoded = try JSONEncoder().encode(ToolNotFoundBehavior.returnErrorToModel)
        let decoded = try JSONDecoder().decode(ToolNotFoundBehavior.self, from: encoded)

        #expect(decoded == .returnErrorToModel)
    }

    @Test
    func resetToolChoiceClearsForcedToolChoiceAfterToolUse() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_again", name: "again", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in
            .text("again")
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.function(tool)],
            model: model,
            modelSettings: ModelSettings(toolChoice: .required)
        )

        _ = try await Runner.run(agent: agent, input: "Run")

        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests.first?.settings.toolChoice == .required)
        #expect(requests.last?.settings.toolChoice == nil)
    }

    @Test
    func resetToolChoiceStateSurvivesApprovalInterruptionResume() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_again", name: "again", arguments: [:]))
            ]),
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_sensitive", name: "sensitive", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let again = FunctionTool<Void>(name: "again", description: "Again.") { _, _ in
            .text("again")
        }
        let sensitive = FunctionTool<Void>(
            name: "sensitive",
            description: "Needs approval.",
            approval: { _ in true }
        ) { _, _ in
            .text("sensitive")
        }
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.function(again), .function(sensitive)],
            model: model,
            modelSettings: ModelSettings(toolChoice: .required)
        )

        let interrupted = try await Runner.run(agent: agent, input: "Run")

        #expect(interrupted.isInterrupted)
        var state = try #require(interrupted.state(as: Void.self))
        #expect(state.toolUseTrackerSnapshot == ["Assistant": ["again"]])
        state.approve(try #require(interrupted.interruptions.first))

        let resumed = try await Runner.run(state: state)

        #expect(resumed.finalOutput == "Done.")
        let requests = await model.requests()
        #expect(requests.count == 3)
        #expect(requests[0].settings.toolChoice == .required)
        #expect(requests[1].settings.toolChoice == nil)
        #expect(requests[2].settings.toolChoice == nil)
    }

    @Test
    func resetToolChoiceTrackingUsesAgentIdentityDuringRun() async throws {
        let firstModel = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_first", name: "first", arguments: [:]))
            ]),
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_handoff",
                    name: "transfer_to_assistant",
                    arguments: [:]
                ))
            ])
        ])
        let secondModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let firstTool = FunctionTool<Void>(name: "first", description: "First.") { _, _ in
            .text("first")
        }
        let secondAgent = Agent<Void>(
            name: "Assistant",
            model: secondModel,
            modelSettings: ModelSettings(toolChoice: .required)
        )
        let firstAgent = Agent<Void>(
            name: "Assistant",
            tools: [firstTool],
            handoffs: [Handoff(to: secondAgent)],
            model: firstModel,
            modelSettings: ModelSettings(toolChoice: .required)
        )

        let result = try await Runner.run(agent: firstAgent, input: "Run")

        #expect(result.finalOutput == "Done.")
        let firstRequests = await firstModel.requests()
        let secondRequests = await secondModel.requests()
        #expect(firstRequests.count == 2)
        #expect(firstRequests[0].settings.toolChoice == .required)
        #expect(firstRequests[1].settings.toolChoice == nil)
        #expect(secondRequests.first?.settings.toolChoice == .required)
    }

    @Test
    func runConfigCallModelInputFilterCanRewriteModelData() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            instructions: .text("Original instructions."),
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Original input",
            runConfig: RunConfig(callModelInputFilter: { data in
                ModelInputData(
                    input: [.message(AgentMessage(role: .user, content: "Filtered input"))],
                    instructions: "\(data.agent.name): filtered instructions"
                )
            })
        )

        let requests = await model.requests()
        #expect(requests.first?.instructions == "Assistant: filtered instructions")
        #expect(requests.first?.input == [.message(AgentMessage(role: .user, content: "Filtered input"))])
    }

    @Test
    func callModelInputFilterDoesNotChangeResultReplayHistory() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Filtered."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Original input",
            runConfig: RunConfig(callModelInputFilter: { _ in
                ModelInputData(
                    input: [.message(AgentMessage(role: .user, content: "Filtered input"))],
                    instructions: nil
                )
            })
        )

        #expect(result.toInputList(mode: .normalized) == result.toInputList())
        #expect(!result.toInputList().contains(.message(AgentMessage(role: .user, content: "Filtered input"))))
    }

    @Test
    func reasoningItemIDPolicyOmitsFollowUpReasoningIDs() async throws {
        let reasoning: JSONValue = [
            "type": "reasoning",
            "id": "rs_first",
            "summary": [
                ["type": "summary_text", "text": "Thinking"]
            ]
        ]
        let sanitizedReasoning: ModelInputItem = .reasoning([
            "type": "reasoning",
            "summary": [
                ["type": "summary_text", "text": "Thinking"]
            ]
        ])
        let model = FakeModel([
            ModelResponse(output: [
                .reasoning(reasoning),
                .functionCall(FunctionCall(callID: "call_first", name: "foo", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let tool = FunctionTool<Void>(name: "foo", description: "Foo.") { _, _ in
            .text("tool_result")
        }
        let agent = Agent<Void>(name: "Assistant", tools: [tool], model: model)

        let result = try await Runner.run(
            agent: agent,
            input: "Run",
            runConfig: RunConfig(reasoningItemIDPolicy: .omit)
        )

        #expect(result.finalOutput == "Done.")
        let requests = await model.requests()
        let secondTurnReasoning = requests.dropFirst().first?.input.first {
            if case .reasoning = $0 {
                return true
            }
            return false
        }
        #expect(secondTurnReasoning == sanitizedReasoning)
        let historyReasoning = result.toInputList().first {
            if case .reasoning = $0 {
                return true
            }
            return false
        }
        #expect(historyReasoning == sanitizedReasoning)
    }
}
