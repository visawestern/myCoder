import Testing
import Foundation
@testable import myCoder

/// Чистые хелперы DirectWebAPIClient: конвертация cookie, парсинг SSE,
/// извлечение токенов из заголовков и cookie.
@MainActor
@Suite("DirectWebAPIClient чистые хелперы")
struct DirectWebAPIClientLogicTests {

    @Test("parseSSEEvent разбирает полный формат")
    func parseFullSSEEvent() {
        let raw = """
        event: message
        data: {"choices":[{"delta":{"content":"Hello"}}]}
        id: evt_123
        retry: 5000
        """
        let event = DirectWebAPIClient.parseSSEEvent(raw)
        #expect(event?.type == "message")
        #expect(event?.data == #"{"choices":[{"delta":{"content":"Hello"}}]}"#)
        #expect(event?.id == "evt_123")
        #expect(event?.retry == 5000)
    }

    @Test("parseSSEEvent: пустые данные → nil, многострочные data склеиваются")
    func parseSSEMultiLineData() {
        #expect(DirectWebAPIClient.parseSSEEvent("data:") == nil)
        let multi = "data: line1\ndata: line2"
        let event = DirectWebAPIClient.parseSSEEvent(multi)
        #expect(event?.data == "line1\nline2")
        #expect(event?.type == "message", "дефолтный тип — message")
    }

    @Test("extractToken: из заголовка (с/без Bearer)")
    func extractTokenFromHeaders() {
        #expect(DirectWebAPIClient.extractToken(from: ["Authorization": "Bearer abc123"]) == "abc123")
        #expect(DirectWebAPIClient.extractToken(from: ["Authorization": "plain"]) == "plain")
        #expect(DirectWebAPIClient.extractToken(from: [:]) == nil)
        #expect(DirectWebAPIClient.extractToken(from: ["X-Key": "v"], headerName: "X-Key") == "v")
    }

    @Test("extractToken: из cookie по имени")
    func extractTokenFromCookies() {
        let cookies = [
            BrowserCookie(name: "session_token", value: "tok-1", domain: "x"),
            BrowserCookie(name: "other", value: "tok-2", domain: "x")
        ]
        #expect(DirectWebAPIClient.extractToken(from: cookies, tokenName: "session_token") == "tok-1")
        #expect(DirectWebAPIClient.extractToken(from: cookies, tokenName: "missing") == nil)
    }

    @Test("convertCookies преобразует BrowserCookie в HTTPCookie")
    func convertCookiesMaps() {
        let browser = BrowserCookie(name: "a", value: "b", domain: "example.com", path: "/", expiresEpoch: 1_800_000_000)
        let cookies = DirectWebAPIClient.convertCookies([browser])
        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "a")
        #expect(cookies.first?.value == "b")
        #expect(cookies.first?.domain == "example.com")
        #expect(cookies.first?.path == "/")
        #expect(DirectWebAPIClient.convertCookies([]).isEmpty)
    }
}
