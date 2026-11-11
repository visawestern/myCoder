import Foundation
import Testing
@testable import myCoder

/// Вход в веб-провайдера подтверждается ЖИВОЙ проверкой страницы в AntiBrowser,
/// а не файлами cookie на диске (решение владельца 11.11.2026).
///
/// `WebLoginVerificationLogic` — чистая функция: получает cookie текущей
/// вкладки и текст страницы, возвращает вердикт. Файлы `cookies.json` и
/// `session.json` больше не создаются: у AntiBrowser постоянный профиль,
/// поэтому вход переживает перезапуск сам по себе.
@MainActor
@Suite("Проверка входа веб-провайдера без файлов cookie")
struct WebLoginVerificationLogicTests {

    private func cookie(_ name: String, value: String = "v") -> BrowserCookie {
        BrowserCookie(name: name, value: value, domain: "example.com")
    }

    @Test("Вход подтверждён, если на вкладке есть cookie авторизации")
    func confirmedWithAuthCookie() {
        let verdict = WebLoginVerificationLogic.verdict(
            vendor: .kimi,
            cookies: [cookie("_ga"), cookie("kimi-auth")],
            pageText: "Чат Kimi"
        )
        #expect(verdict == .confirmed)
    }

    @Test("Анонимные cookie не считаются входом")
    func anonymousCookiesAreNotALogin() {
        let verdict = WebLoginVerificationLogic.verdict(
            vendor: .kimi,
            cookies: [cookie("_ga"), cookie("theme"), cookie("g_state")],
            pageText: "Чат Kimi"
        )
        #expect(verdict == .missingAuthCookie)
    }

    @Test("Экран входа сильнее случайной cookie авторизации")
    func loginWallWinsOverStaleCookie() {
        let verdict = WebLoginVerificationLogic.verdict(
            vendor: .chatgpt,
            cookies: [cookie("__Secure-next-auth.session-token")],
            pageText: "Войдите в систему, чтобы продолжить"
        )
        #expect(verdict == .loginWall)
    }

    @Test("Свой веб-провайдер подтверждается любой непустой cookie")
    func customVendorAcceptsAnyCookie() {
        let verdict = WebLoginVerificationLogic.verdict(
            vendor: .custom,
            cookies: [cookie("sid")],
            pageText: "Мой чат"
        )
        #expect(verdict == .confirmed)
    }

    @Test("Пустой список cookie — это не вход")
    func emptyCookiesAreNotALogin() {
        let verdict = WebLoginVerificationLogic.verdict(
            vendor: .custom,
            cookies: [],
            pageText: "Мой чат"
        )
        #expect(verdict == .missingAuthCookie)
    }

    @Test("Маркеры экрана входа распознаются на русском и английском")
    func loginWallMarkersAreRecognized() {
        #expect(WebLoginVerificationLogic.isLoginWall(pageText: "Войдите в систему"))
        #expect(WebLoginVerificationLogic.isLoginWall(pageText: "Sign up free"))
        #expect(WebLoginVerificationLogic.isLoginWall(pageText: "Continue with Google"))
        #expect(!WebLoginVerificationLogic.isLoginWall(pageText: "Обычный чат без ограничений"))
    }

    @Test("Сообщения объясняют, что делать дальше")
    func messagesAreActionable() {
        #expect(WebLoginVerificationLogic.message(for: .confirmed).lowercased().contains("подтвержд"))
        let missing = WebLoginVerificationLogic.message(for: .missingAuthCookie).lowercased()
        #expect(missing.contains("войд"))
        let wall = WebLoginVerificationLogic.message(for: .loginWall).lowercased()
        #expect(wall.contains("вход") || wall.contains("войд"))
    }
}
