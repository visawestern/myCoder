import Testing
import Foundation
@testable import myCoder

/// Audit 2026-09-08 regression: `/api/send-and-wait` used to return
/// "status":"answered" carrying internal UI status lines instead of the
/// provider's real text ("Thinking… (K3)", "Sent via browserAutomation…").
@Suite("send-and-wait real-answer detection (audit 2026-09-08)")
struct SendWaitAnswerLogicTests {

    @Test func thinkingPlaceholderIsNotAnAnswer() {
        #expect(!SendWaitAnswerLogic.isRealAnswer("Thinking… (K3)"))
        #expect(!SendWaitAnswerLogic.isRealAnswer("Thinking… (Sonnet 5)"))
    }

    @Test func smartSendStatusIsNotAnAnswer() {
        #expect(!SendWaitAnswerLogic.isRealAnswer("Sent via browserAutomation, waiting for response…"))
        #expect(!SendWaitAnswerLogic.isRealAnswer("Sent via directAPI, waiting for response…"))
    }

    @Test func emptyTextIsNotAnAnswer() {
        #expect(!SendWaitAnswerLogic.isRealAnswer(""))
        #expect(!SendWaitAnswerLogic.isRealAnswer("   \n  "))
    }

    @Test func realProviderTextIsAnAnswer() {
        #expect(SendWaitAnswerLogic.isRealAnswer("TEST-OK-QWEN"))
        #expect(SendWaitAnswerLogic.isRealAnswer("Here is the plan you asked for: …"))
    }

    @Test func routeFooterNoLongerPollutesAnswers() {
        // Since 2026-09-08 route metadata ships as routeInfo parts (header
        // chips), so a clean answer must NOT contain the footer — and a
        // status line with a footer-shaped text is still a status line.
        #expect(!SendWaitAnswerLogic.isRealAnswer("Sent via browserAutomation\n\nBrowser route: Qwen · chat 1"))
        #expect(!SendWaitAnswerLogic.isRealAnswer("Thinking… (K3)\n\nBrowser route: Kimi · chat 2"))
    }

    @Test func toolProgressIsNotAnAnswer() {
        #expect(!SendWaitAnswerLogic.isRealAnswer("⏳ Running tools..."))
        #expect(!SendWaitAnswerLogic.isRealAnswer("Refreshing model catalog before retry…"))
    }
}

/// Audit 2026-09-08 regression: the Kimi history page (/chat/history) was
/// accepted as a conversation identity ("history") and bound sends to it.
@Suite("remote chat identity placeholders (audit 2026-09-08)")
struct RemoteChatIdentityPlaceholderTests {

    @Test func routeLiteralsAreRejected() {
        #expect(WebRemoteChatIdentityLogic.firstValid(["history"]) == nil)
        #expect(WebRemoteChatIdentityLogic.firstValid(["new"]) == nil)
        #expect(WebRemoteChatIdentityLogic.firstValid(["settings"]) == nil)
        #expect(WebRemoteChatIdentityLogic.firstValid(["search"]) == nil)
        #expect(WebRemoteChatIdentityLogic.firstValid(["login"]) == nil)
    }

    @Test func realUUIDStillAccepted() {
        let id = "f73a5267-e961-41f4-899d-c6b1fc8d32c5"
        #expect(WebRemoteChatIdentityLogic.firstValid([id]) == id)
    }

    @Test func placeholderFallsThroughToNextCandidate() {
        let real = "f73a5267-e961-41f4-899d-c6b1fc8d32c5"
        #expect(WebRemoteChatIdentityLogic.firstValid(["history", real]) == real)
    }
}
