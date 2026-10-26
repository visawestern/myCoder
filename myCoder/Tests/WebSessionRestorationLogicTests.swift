import Foundation
import Testing
@testable import myCoder

@Suite("WEB-LOGIN-13: browser session restoration payload")
struct WebSessionRestorationLogicTests {
    @Test("restoration payload preserves cookies and localStorage")
    func payloadPreservesBothStateStores() {
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "sid", value: "abc", domain: "kimi.com")],
            localStorage: ["account_id": "acct-1", "csrf": "token"],
            savedAt: Date(timeIntervalSince1970: 123)
        )
        let payload = WebSessionRestorationLogic.payload(from: store)
        #expect(payload.cookies == store.cookies)
        #expect(payload.localStorage == store.localStorage)
        #expect(payload.localStorage["account_id"] == "acct-1")
    }

    @Test("empty localStorage remains a valid cookie-only session payload")
    func emptyLocalStorageDoesNotDiscardCookies() {
        let cookies = [BrowserCookie(name: "sid", value: "abc", domain: "qwen.ai")]
        let payload = WebSessionRestorationLogic.payload(
            from: WebSessionStore(cookies: cookies, localStorage: [:], savedAt: Date())
        )
        #expect(payload.cookies == cookies)
        #expect(payload.localStorage.isEmpty)
    }

    @Test("localStorage restoration is ordered after target navigation and followed by reload")
    func restorationOrderUsesTargetOrigin() {
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "sid", value: "abc", domain: "kimi.com")],
            localStorage: ["account_id": "acct-1"],
            savedAt: Date()
        )
        #expect(WebSessionRestorationLogic.steps(from: store) == [
            .setCookies,
            .navigateToTarget,
            .setLocalStorage,
            .reloadTarget
        ])
    }

    @Test("cookie-only restoration does not add an unnecessary reload")
    func cookieOnlyRestorationHasNoStorageSteps() {
        let store = WebSessionStore(cookies: [], localStorage: [:], savedAt: Date())
        #expect(WebSessionRestorationLogic.steps(from: store) == [.setCookies, .navigateToTarget])
    }
}
