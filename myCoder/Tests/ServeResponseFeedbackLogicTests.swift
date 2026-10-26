import Testing
@testable import myCoder

@Suite("APP-06 Serve response feedback")
struct ServeResponseFeedbackLogicTests {
    @Test("blank direct Serve completion returns actionable failure")
    func blankCompletionFails() {
        let message = ServeResponseFeedbackLogic.failureMessage(
            text: "  ",
            reasoning: "\n",
            hasToolActivity: false
        )
        #expect(message?.localizedCaseInsensitiveContains("empty") == true)
        #expect(message?.localizedCaseInsensitiveContains("retry") == true)
    }

    @Test("reasoning-only or tool-bearing Serve completion remains valid")
    func nonTextActivityRemainsValid() {
        #expect(ServeResponseFeedbackLogic.failureMessage(
            text: "",
            reasoning: "thinking",
            hasToolActivity: false
        ) == nil)
        #expect(ServeResponseFeedbackLogic.failureMessage(
            text: "",
            reasoning: "",
            hasToolActivity: true
        ) == nil)
        #expect(ServeResponseFeedbackLogic.failureMessage(
            text: "answer",
            reasoning: "",
            hasToolActivity: false
        ) == nil)
    }
}
