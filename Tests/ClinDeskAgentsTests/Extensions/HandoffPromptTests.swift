import Testing
import ClinDeskAgents

@Suite
struct HandoffPromptTests {
    @Test
    func handoffPromptAddsRecommendedPrefix() {
        let prompt = HandoffPrompt.promptWithHandoffInstructions("Book appointments.")

        #expect(prompt.hasPrefix(HandoffPrompt.recommendedPromptPrefix))
        #expect(prompt.hasSuffix("Book appointments."))
    }
}
