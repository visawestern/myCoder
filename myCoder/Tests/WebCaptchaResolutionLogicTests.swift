import Testing
@testable import myCoder

@Suite("WEB-07 captcha resolution policy")
struct WebCaptchaResolutionLogicTests {
    @Test("captcha state keeps the agent waiting")
    func captchaKeepsWaiting() {
        #expect(WebCaptchaResolutionLogic.action(for: WebSessionState.captchaRequired) == .wait)
    }

    @Test("connected state resumes the same browser turn")
    func connectedResumes() {
        #expect(WebCaptchaResolutionLogic.action(for: WebSessionState.connected) == .resume)
    }

    @Test("logout aborts captcha wait")
    func logoutAborts() {
        #expect(WebCaptchaResolutionLogic.action(for: WebSessionState.loggedOut) == .abort)
    }
}
