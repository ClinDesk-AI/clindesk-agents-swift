import Testing
import ClinDeskAgents

@Suite
struct FunctionToolNamespaceTests {
    @Test
    func runnerRejectsAmbiguousNamespacedAndDottedFunctionTools() async throws {
        let dotted = FunctionTool<Void>(
            name: "crm.lookup",
            description: "Dotted top-level lookup."
        ) { _, _ in
            .text("dotted")
        }
        var namespaced = FunctionTool<Void>(
            name: "lookup",
            description: "Namespaced lookup."
        ) { _, _ in
            .text("namespaced")
        }
        namespaced.descriptor.namespace = "crm"
        namespaced.descriptor.namespaceDescription = "CRM tools"
        let model = FakeModel([
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Should not call model."))
            ])
        ])
        let agent = Agent<Void>(
            name: "Assistant",
            tools: [.function(dotted), .function(namespaced)],
            model: model
        )

        await #expect(throws: AgentsError.invalidRunConfig(
            "Ambiguous function tool configuration: the qualified name `crm.lookup` is used by multiple tools. Rename the namespace-wrapped function or dotted top-level tool to avoid ambiguous dispatch."
        )) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }

        #expect(await model.requests().isEmpty)
    }

    @Test
    func toolNamespaceAttachesMetadataAndRunnerDispatchesNamespacedCalls() async throws {
        let lookup = FunctionTool<Void>(
            name: "lookup_account",
            description: "Lookup account."
        ) { _, arguments in
            .text("account:\(arguments["customer_id"]?.stringValue ?? "")")
        }
        let namespacedTools = try toolNamespace(
            name: "crm",
            description: "CRM tools",
            tools: [lookup]
        )
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(
                    callID: "call_lookup",
                    name: "lookup_account",
                    namespace: "crm",
                    arguments: ["customer_id": "cus_123"]
                ))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", tools: namespacedTools, model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Done.")
        #expect(namespacedTools.first?.descriptor.qualifiedName == "crm.lookup_account")
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_lookup"
                    && output.output.stringValue == "account:cus_123"
            }
            return false
        } == true)
    }

    @Test
    func duplicateBareFunctionToolsDispatchWithLastWinsPrecedence() async throws {
        let first = FunctionTool<Void>(name: "lookup", description: "First lookup.") { _, _ in
            .text("first")
        }
        let second = FunctionTool<Void>(name: "lookup", description: "Second lookup.") { _, _ in
            .text("second")
        }
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_lookup", name: "lookup", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Done."))
            ])
        ])
        let agent = Agent<Void>(name: "Assistant", tools: [first, second], model: model)

        _ = try await Runner.run(agent: agent, input: "Run")

        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_lookup"
                    && output.output.stringValue == "second"
            }
            return false
        } == true)
    }
}
