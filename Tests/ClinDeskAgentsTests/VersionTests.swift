import Testing
import ClinDeskAgents

@Suite
struct VersionTests {
    @Test
    func exposesPackageAndUpstreamParityVersions() {
        #expect(ClinDeskAgentsVersion.current == "1.0.0")
        #expect(ClinDeskAgentsVersion.upstreamAgentsSDK == "0.17.4")
    }
}
