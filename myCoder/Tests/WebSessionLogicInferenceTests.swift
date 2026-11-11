import Testing
import Foundation
@testable import myCoder

/// Вывод состояния веб-сессии: captcha/лимит/logged-out/connected и
/// порядок шагов восстановления.
@MainActor
@Suite("Инференция состояния веб-сессии")
struct WebSessionLogicInferenceTests {

    @Test("Captcha распознаётся по маркерам")
    func captchaDetection() {
        #expect(WebSessionLogic.detectCaptcha(pageText: "Please verify you are human", url: "https://x"))
        #expect(WebSessionLogic.detectCaptcha(pageText: "", url: "https://challenges.cloudflare.com/"))
        #expect(WebSessionLogic.detectCaptcha(pageText: "hello", url: "https://x/chat") == false)
    }

    @Test("Лимит распознаётся по странице цены/quota")
    func limitDetection() {
        #expect(WebSessionLogic.detectLimitReached(pageText: "", url: "https://kimi.com/membership/pricing?from=okc_limit_notification"))
        #expect(WebSessionLogic.detectLimitReached(pageText: "quota exceeded", url: "https://x"))
        #expect(WebSessionLogic.detectLimitReached(pageText: "Your free quota has been used up", url: "https://x"))
        #expect(WebSessionLogic.detectLimitReached(pageText: "normal", url: "https://x/chat") == false)
        // «conversation is too long» — лимит ДЛИНЫ сессии, а не quota:
        // обрабатывается WebSessionLimitLogic отдельно.
        #expect(WebSessionLimitLogic.isSessionLimitReached(responseText: "conversation is too long"))
        #expect(!WebSessionLimitLogic.isSessionLimitReached(responseText: "normal answer"))
    }

    @Test("inferState: приоритет captcha → лимит → loggedOut → connected")
    func inferStatePriority() {
        #expect(WebSessionLogic.inferState(currentURL: "https://x/chat", hasChatInput: true, pageText: "verify you are human") == .captchaRequired)
        #expect(WebSessionLogic.inferState(currentURL: "https://x/membership/pricing", hasChatInput: false, pageText: "") == .limitReached)
        #expect(WebSessionLogic.inferState(currentURL: "https://x/login", hasChatInput: true, pageText: "") == .loggedOut)
        #expect(WebSessionLogic.inferState(currentURL: "https://x/chat", hasChatInput: false, pageText: "") == .loggedOut)
        #expect(WebSessionLogic.inferState(currentURL: "https://x/chat", hasChatInput: true, pageText: "") == .connected)
    }

    @Test("Payload восстановления переносит cookies и localStorage")
    func restorationPayloadCopiesStore() {
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "a", value: "b", domain: "x", path: "/")],
            localStorage: ["k": "v"],
            savedAt: Date()
        )
        let payload = WebSessionRestorationLogic.payload(from: store)
        #expect(payload.cookies.count == 1)
        #expect(payload.localStorage == ["k": "v"])
    }

    @Test("Шаги восстановления: с localStorage добавляются setLocalStorage + reload")
    func restorationStepsIncludeLocalStorage() {
        let without = WebSessionStore(cookies: [], localStorage: [:], savedAt: Date())
        #expect(WebSessionRestorationLogic.steps(from: without) == [.setCookies, .navigateToTarget])

        let with = WebSessionStore(cookies: [], localStorage: ["k": "v"], savedAt: Date())
        #expect(WebSessionRestorationLogic.steps(from: with) == [.setCookies, .navigateToTarget, .setLocalStorage, .reloadTarget])
    }
}
