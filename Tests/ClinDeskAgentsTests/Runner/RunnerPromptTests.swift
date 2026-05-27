import Testing
import ClinDeskAgents

@Suite
struct RunnerPromptTests {
    @Test
    func resolvesDynamicInstructionsWithContext() async throws {
        struct ClinicContext: Sendable {
            let clinicName: String
        }

        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Ready."))
            ])
        ])
        let agent = Agent<ClinicContext>(
            name: "Assistant",
            instructions: .dynamic { context, _ in
                "You are helping \(context.context?.clinicName ?? "the clinic")."
            },
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hola",
            context: ClinicContext(clinicName: "ClinDesk Clinic")
        )

        let requests = await model.requests()
        #expect(requests.first?.instructions == "You are helping ClinDesk Clinic.")
    }

    @Test
    func agentPublicPromptHelpersResolveInstructionsAndPrompt() async throws {
        struct ClinicContext: Sendable {
            let clinicName: String
            let promptID: String
        }

        let agent = Agent<ClinicContext>(
            name: "Assistant",
            instructions: .dynamic { context, agent in
                "\(agent.name) helps \(context.context?.clinicName ?? "the clinic")."
            },
            prompt: .dynamic { data in
                Prompt(
                    id: data.context.context?.promptID ?? "pmpt_default",
                    version: "2"
                )
            }
        )
        let runContext = RunContext(context: ClinicContext(
            clinicName: "ClinDesk",
            promptID: "pmpt_clindesk"
        ))

        #expect(try await agent.getSystemPrompt(runContext: runContext) == "Assistant helps ClinDesk.")
        #expect(try await agent.getPrompt(runContext: runContext) == Prompt(
            id: "pmpt_clindesk",
            version: "2"
        ))
    }

    @Test
    func passesStaticPromptToLocalModelRequest() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Ready."))
            ])
        ])
        let prompt = Prompt(
            id: "pmpt_local_triage",
            version: "7",
            variables: ["clinic": .string("ClinDesk")]
        )
        let agent = Agent<Void>(
            name: "Assistant",
            prompt: .prompt(prompt),
            model: model
        )

        _ = try await Runner.run(agent: agent, input: "Hola")

        let requests = await model.requests()
        #expect(requests.first?.prompt == prompt)
    }

    @Test
    func resolvesDynamicPromptWithContextAndAgent() async throws {
        struct ClinicContext: Sendable {
            let promptID: String
        }

        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Ready."))
            ])
        ])
        let agent = Agent<ClinicContext>(
            name: "Triage",
            prompt: .dynamic { data in
                Prompt(
                    id: data.context.context?.promptID ?? "pmpt_fallback",
                    variables: ["agent": .string(data.agent.name)]
                )
            },
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hola",
            context: ClinicContext(promptID: "pmpt_contextual")
        )

        let requests = await model.requests()
        #expect(requests.first?.prompt == Prompt(
            id: "pmpt_contextual",
            variables: ["agent": .string("Triage")]
        ))
    }

    @Test
    func typedRunDynamicPromptReceivesPublicAgent() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: #"{"answer":"Ready"}"#))
            ])
        ])
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"]
            ]
        ]
        let agent = Agent<Void>(
            name: "Assistant",
            prompt: .dynamic { data in
                Prompt(
                    id: data.agent.outputSchema == nil ? "pmpt_public" : "pmpt_execution",
                    variables: ["agent": .string(data.agent.name)]
                )
            },
            model: model
        )

        _ = try await Runner.run(
            agent: agent,
            input: "Hi",
            outputType: StructuredAnswer.self,
            outputSchema: schema
        )

        let requests = await model.requests()
        #expect(requests.first?.prompt == Prompt(
            id: "pmpt_public",
            variables: ["agent": .string("Assistant")]
        ))
        #expect(requests.first?.outputSchema?.name == "StructuredAnswer")
    }

    @Test
    func modelProviderResolvesNamedModel() async throws {
        let namedModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Named model response."))
            ])
        ])
        let fallbackModel = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Fallback."))
            ])
        ])
        let provider = StaticModelProvider(
            defaultModel: fallbackModel,
            namedModels: ["local-clinic": namedModel]
        )
        let agent = Agent<Void>(name: "Assistant", modelName: "local-clinic")

        let result = try await Runner.run(agent: agent, input: "Hi", modelProvider: provider)

        #expect(result.finalOutput == "Named model response.")
    }
}
