import Testing
@testable import myCoder

@Suite("WEB-05 browser transport lifecycle")
struct WebBrowserTransportLogicTests {
    @Test("navigation timeout is a failure, not an apparent success")
    func navigationTimeoutFailsClosed() {
        #expect(WebBrowserTransportLogic.navigationOutcome(documentReady: true) == .ready)
        #expect(WebBrowserTransportLogic.navigationOutcome(documentReady: false) == .timedOut)
        #expect(WebBrowserTransportLogic.navigationTimeoutMessage.contains("ready"))
    }

    @Test("cookie restoration retains security attributes")
    func cookieAttributesArePreserved() {
        let cookie = BrowserCookie(
            name: "sid",
            value: "abc",
            domain: "example.com",
            httpOnly: true,
            secure: true
        )
        let attributes = WebCookieRestoreLogic.attributes(for: cookie)
        #expect(attributes.secure)
        #expect(attributes.httpOnly)
    }

    @Test("cookie restoration does not invent security attributes")
    func cookieAttributesRemainFalseWhenUnset() {
        let cookie = BrowserCookie(
            name: "sid",
            value: "abc",
            domain: "example.com",
            httpOnly: false,
            secure: false
        )
        let attributes = WebCookieRestoreLogic.attributes(for: cookie)
        #expect(!attributes.secure)
        #expect(!attributes.httpOnly)
    }
}
