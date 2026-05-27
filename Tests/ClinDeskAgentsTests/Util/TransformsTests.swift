import Testing
import ClinDeskAgents

@Suite
struct TransformsTests {
    @Test
    func transformStringFunctionStyleMirrorsUpstreamRules() {
        #expect(TransformUtils.transformStringFunctionStyle("Lookup Account") == "lookup_account")
        #expect(TransformUtils.transformStringFunctionStyle("Billing & Claims") == "billing___claims")
        #expect(TransformUtils.transformStringFunctionStyle("already_valid_123") == "already_valid_123")
        #expect(TransformUtils.transformStringFunctionStyle("café") == "caf_")
    }

    @Test
    func agentAsToolDefaultNameUsesFunctionStyleTransform() {
        let agent = Agent<Void>(name: "Billing & Claims")
        let tool = agent.asTool()

        #expect(tool.descriptor.name == "billing___claims")
    }

    @Test
    func handoffDefaultToolNameUsesFunctionStyleTransferPrefix() {
        #expect(Handoff<Void>.defaultToolName(for: "Billing & Claims") == "transfer_to_billing___claims")
        #expect(Handoff<Void>.defaultToolName(for: "Triage Nurse") == "transfer_to_triage_nurse")
    }
}
