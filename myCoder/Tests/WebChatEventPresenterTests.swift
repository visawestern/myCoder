import Testing
import Foundation
@testable import myCoder

@Suite("Web chat event presenter — captcha in chat (plan Раздел 12 Блок 3 п.34)")
struct WebChatEventPresenterTests {
    init() { LocalizationRuntime.currentLanguage = .english }

    @Test func captchaEventProducesInlineCaptcha() {
        let png = Data("PNGDATA".utf8)
        let p = WebChatEventPresenter.present(.captchaDetected(screenshotPNG: png))
        if case .captcha(let b64, let note) = p {
            #expect(b64 == png.base64EncodedString())
            #expect(note.contains("captcha"))
        } else {
            Issue.record("expected .captcha, got \(p)")
        }
    }

    @Test func finalEventProducesAnswer() {
        #expect(WebChatEventPresenter.present(.final("done")) == .answer("done"))
    }

    @Test func errorEventProducesError() {
        #expect(WebChatEventPresenter.present(.error("boom")) == .error("boom"))
    }

    @Test func streamingSuppressed() {
        #expect(WebChatEventPresenter.present(.streaming("partial")) == .none)
    }

    @Test func toolEventsAreStructuredNotStatusLines() {
        // Tool calls/results render as spoiler parts in Message.parts with
        // full args and results; the presenter no longer flattens them to
        // "↪ name" / "✓ name" status lines.
        let call = WebToolCall(name: "read_file", arguments: ["path": "a"])
        #expect(WebChatEventPresenter.present(.toolCall(call)) == .none)
        #expect(WebChatEventPresenter.present(.toolResult(name: "read_file", result: "x")) == .none)
    }

    @Test func approvalRequestIsStructuredAndBlocking() {
        // The blocking approval request renders as an interactive Allow/Deny
        // card from Message.parts — not a flat status line — and blocks the
        // driver until the user answers.
        let request = WebToolApprovalRequest(id: "req-1", tool: "write_file", message: "needs approval")
        #expect(WebChatEventPresenter.present(.approvalRequest(request)) == .none)
        #expect(WebChatEventPresenter.blocksUntilUserAction(.approvalRequest(request)))
    }

    @Test func approvalBoxResolvesOnlyCurrentRequest() {
        // The one-slot mailbox: only the pending request can be resolved; a
        // stale or duplicate answer is dropped so the driver sees exactly one
        // verdict per request.
        let box = WebToolApprovalBox()
        let first = WebToolApprovalRequest(id: "a", tool: "t", message: "m")
        box.post(first)
        box.resolve(id: "stale", approved: true)   // wrong id → dropped
        #expect(box.verdict(for: "a") == nil)
        box.resolve(id: "a", approved: false)
        #expect(box.verdict(for: "a") == false)
        #expect(box.current() == nil)
    }

    @Test func approvalBoxAwaitTimesOutWithoutAnswer() {
        // With no UI answer the bounded wait returns nil so the driver can
        // decline honestly instead of hanging forever.
        let box = WebToolApprovalBox()
        let request = WebToolApprovalRequest(id: "b", tool: "t", message: "m")
        box.post(request)
        #expect(box.awaitAnswer(timeoutSeconds: 0) == nil)
    }

    @Test func approvalBoxDeliversAnswerAcrossThreads() {
        // The UI resolves on the main actor while the driver waits on a
        // background task — the mailbox must hand the verdict over.
        let box = WebToolApprovalBox()
        let request = WebToolApprovalRequest(id: "c", tool: "t", message: "m")
        box.post(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            box.resolve(id: "c", approved: true)
        }
        #expect(box.awaitAnswer(timeoutSeconds: 5) == true)
    }

    @Test func toolPartsBoxCompletesRunningCallWithResult() {
        // A toolCall event appends a running part; the matching toolResult
        // folds the result into that part. Completed calls come first (in
        // completion order), still-running calls keep the running state at
        // the end so the inspector shows live progress.
        let box = WebToolPartsBox()
        box.appendRunning(name: "list_dir", args: "path=.", partID: "p1")
        box.appendRunning(name: "grep", args: "pattern=x", partID: "p2")
        box.completeLast(name: "grep", result: "no matches")
        let parts = box.parts
        #expect(parts.count == 2)
        // grep completed with its result.
        if case .toolCall(let name, _, let result, let id)? = parts.first {
            #expect(name == "grep")
            #expect(id == "p2")
            #expect(result == "no matches")
        } else {
            Issue.record("expected completed grep part first")
        }
        // list_dir is still running (result == nil).
        if case .toolCall(let name, _, let result, let id)? = parts.last {
            #expect(name == "list_dir")
            #expect(id == "p1")
            #expect(result == nil)
        } else {
            Issue.record("expected running list_dir part last")
        }
    }

    @Test func sessionEventsAreStatus() {
        #expect(WebChatEventPresenter.present(.sessionLimitReached) != .none)
        #expect(WebChatEventPresenter.present(.sessionRestarted) != .none)
        #expect(WebChatEventPresenter.present(.promptSplit(parts: 3)) != .none)
    }

    @Test func captchaAndLogoutBlockUntilAction() {
        #expect(WebChatEventPresenter.blocksUntilUserAction(.captchaDetected(screenshotPNG: Data())))
        #expect(WebChatEventPresenter.blocksUntilUserAction(.loggedOut))
        #expect(!WebChatEventPresenter.blocksUntilUserAction(.final("x")))
        #expect(!WebChatEventPresenter.blocksUntilUserAction(.streaming("y")))
    }
}
