import Foundation
import Testing
@testable import myCoder

@Suite("Web send completion journal")
struct WebSendCompletionLogicTests {
    @Test("visible final answer is the only successful completion event")
    func visibleFinalCompletes() {
        #expect(WebSendCompletionLogic.recordsCompletion(for: .final("done")))
    }

    @Test("failure and user-action events are not completed sends")
    func failureDoesNotComplete() {
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .loggedOut))
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .captchaDetected(screenshotPNG: Data())))
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .iterationLimitReached))
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .modelInjectionFailed("not found")))
    }

    @Test("honest turn error concludes the turn without a second verdict line")
    func honestErrorCompletes() {
        // Audit 2026-09-09: the bubble already carries the real error text;
        // without this the caller appends a misleading "did not produce a
        // verified final answer" line after it.
        #expect(WebSendCompletionLogic.recordsCompletion(for: .error("timeout")))
    }

    @Test("blank final answer is not a successful completion")
    func blankFinalDoesNotComplete() {
        #expect(!WebSendCompletionLogic.recordsCompletion(for: .final("  \n")))
    }
}
