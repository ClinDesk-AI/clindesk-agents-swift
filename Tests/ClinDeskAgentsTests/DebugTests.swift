import Testing
import ClinDeskAgents

@Suite
struct DebugTests {
    @Test
    func debugFlagEnabledMirrorsUpstreamTruthiness() {
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: [:]) == false)
        #expect(DebugOptions.debugFlagEnabled("FLAG", default: true, environment: [:]) == true)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "0"]) == false)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "1"]) == true)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "true"]) == true)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "TRUE"]) == true)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "false"]) == false)
        #expect(DebugOptions.debugFlagEnabled("FLAG", environment: ["FLAG": "yes"]) == false)
    }

    @Test
    func dontLogModelDataDefaultsToTrueAndUsesLocalEnvironmentName() {
        #expect(DebugOptions.dontLogModelData(environment: [:]) == true)
        #expect(DebugOptions.dontLogModelData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_MODEL_DATA": "0"
        ]) == false)
        #expect(DebugOptions.dontLogModelData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_MODEL_DATA": "1"
        ]) == true)
        #expect(DebugOptions.dontLogModelData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_MODEL_DATA": "true"
        ]) == true)
        #expect(DebugOptions.dontLogModelData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_MODEL_DATA": "false"
        ]) == false)
    }

    @Test
    func dontLogToolDataDefaultsToTrueAndUsesLocalEnvironmentName() {
        #expect(DebugOptions.dontLogToolData(environment: [:]) == true)
        #expect(DebugOptions.dontLogToolData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_TOOL_DATA": "0"
        ]) == false)
        #expect(DebugOptions.dontLogToolData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_TOOL_DATA": "1"
        ]) == true)
        #expect(DebugOptions.dontLogToolData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_TOOL_DATA": "true"
        ]) == true)
        #expect(DebugOptions.dontLogToolData(environment: [
            "CLINDESK_AGENTS_DONT_LOG_TOOL_DATA": "false"
        ]) == false)
    }

    @Test
    func agentsLoggerUsesStableLocalNamespace() {
        #expect(AgentsLogger.subsystem == "com.clindesk.agents")
        #expect(AgentsLogger.category == "ClinDeskAgents")
    }
}
