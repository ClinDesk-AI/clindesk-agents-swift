import Testing
import ClinDeskAgents

@Suite
struct AgentToolDescriptorTests {
    @Test
    func agentAsToolUsesFunctionStyleDefaults() async throws {
        let child = Agent<Void>(name: "Billing Agent!")
        let tool = child.asTool()

        #expect(tool.descriptor.name == "billing_agent_")
        #expect(tool.descriptor.description == "")
        #expect(tool.descriptor.parameters["properties"]?["input"]?["type"]?.stringValue == "string")
        #expect(tool.descriptor.parameters["required"]?.arrayValue == [.string("input")])
        #expect(tool.descriptor.parameters["additionalProperties"] == .bool(false))
        #expect(tool.descriptor.strict)
    }
}
