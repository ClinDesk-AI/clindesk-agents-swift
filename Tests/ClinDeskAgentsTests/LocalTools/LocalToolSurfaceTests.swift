import Testing
import ClinDeskAgents

@Suite
struct LocalToolSurfaceTests {
    @Test
    func shellToolUsesLocalEnvironment() throws {
        let local = try ShellTool<Void>(executor: { _ in .text("ok") })
        #expect(local.descriptor.environment == ["type": "local"])
        #expect(local.isLocal)
    }

    @Test
    func localShellToolExposesUpstreamName() {
        let tool = LocalShellTool<Void> { _ in "ok" }
        #expect(tool.name == "local_shell")
        #expect(tool.descriptor == LocalShellToolDescriptor())
    }
}
