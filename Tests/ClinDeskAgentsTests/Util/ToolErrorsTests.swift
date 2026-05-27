import Testing
import ClinDeskAgents

@Suite
struct ToolErrorsTests {
    @Test
    func traceToolErrorRedactsWhenSensitiveDataIsDisabled() {
        #expect(ToolErrorUtils.traceToolError(
            traceIncludeSensitiveData: true,
            errorMessage: "secret failure"
        ) == "secret failure")
        #expect(ToolErrorUtils.traceToolError(
            traceIncludeSensitiveData: false,
            errorMessage: "secret failure"
        ) == ToolErrorUtils.redactedToolErrorMessage)
    }
}
