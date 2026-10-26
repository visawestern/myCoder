import Testing
@testable import myCoder

@Suite("Provider response validation")
struct ProviderResponseValidationLogicTests {
    @Test("whitespace-only provider content is not a usable response")
    func whitespaceIsRejected() {
        #expect(!ProviderResponseValidationLogic.hasVisibleContent("  \n\t"))
    }

    @Test("meaningful provider content is accepted")
    func meaningfulContentIsAccepted() {
        #expect(ProviderResponseValidationLogic.hasVisibleContent("answer"))
    }

    @Test("a completed Serve turn with no text, reasoning, or tools is rejected")
    func blankCompletedTurnIsRejected() {
        #expect(ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: " ",
            reasoning: "\n",
            hasToolActivity: false
        ))
        #expect(!ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: "answer",
            reasoning: "",
            hasToolActivity: false
        ))
        #expect(!ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: "",
            reasoning: "thinking",
            hasToolActivity: false
        ))
        #expect(!ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: "",
            reasoning: "",
            hasToolActivity: true
        ))
    }

    @Test("empty completion has actionable retry guidance")
    func emptyCompletionMessageIsActionable() {
        let message = ProviderResponseValidationLogic.emptyCompletionMessage
        #expect(message.localizedCaseInsensitiveContains("empty"))
        #expect(message.localizedCaseInsensitiveContains("retry"))
    }
}
