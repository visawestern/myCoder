import Foundation
import Testing
@testable import myCoder

@Suite("WEB-07 live captcha browser presentation")
struct WebCaptchaPresentationLogicTests {
    @Test("captcha event opens the live browser solver")
    func captchaOpensSolver() {
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.captchaDetected(screenshotPNG: Data())) == .showSolver)
    }

    @Test("final and terminal errors dismiss the solver")
    func terminalEventsDismissSolver() {
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.final("done")) == .dismissSolver)
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.error("failed")) == .dismissSolver)
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.loggedOut) == .dismissSolver)
    }

    @Test("all terminal driver outcomes dismiss the solver")
    func allTerminalEventsDismissSolver() {
        #expect(WebCaptchaPresentationLogic.action(for: .iterationLimitReached) == .dismissSolver)
        #expect(WebCaptchaPresentationLogic.action(for: .approvalRequired(tool: "run_command", message: "approval")) == .dismissSolver)
        #expect(WebCaptchaPresentationLogic.action(for: .modelInjectionFailed("missing")) == .dismissSolver)
        #expect(WebCaptchaPresentationLogic.action(for: .effortInjectionFailed("missing")) == .dismissSolver)
    }

    @Test("ordinary progress does not change solver visibility")
    func progressDoesNothing() {
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.streaming("partial")) == .none)
        #expect(WebCaptchaPresentationLogic.action(for: WebChatEvent.toolResult(name: "read_file", result: "ok")) == .none)
    }
}
