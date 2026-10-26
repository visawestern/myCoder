import Testing
import Foundation
@testable import myCoder

@Suite("DirectWebAPIClient Tests")
struct DirectWebAPIClientTests {

    // MARK: - DirectAPIResult Tests

    @Test("DirectAPIResult encodes and decodes correctly")
    func testDirectAPIResultCodable() throws {
        let result = DirectAPIResult(
            success: true,
            response: "Hello!",
            error: nil,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            duration: 1.5,
            wasStreaming: false
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DirectAPIResult.self, from: data)

        #expect(decoded.success == true)
        #expect(decoded.response == "Hello!")
        #expect(decoded.error == nil)
        #expect(decoded.statusCode == 200)
        #expect(decoded.duration == 1.5)
        #expect(decoded.wasStreaming == false)
    }

    @Test("DirectAPIResult handles error case")
    func testDirectAPIResultError() throws {
        let result = DirectAPIResult(
            success: false,
            response: nil,
            error: "HTTP 401",
            statusCode: 401,
            headers: [:],
            duration: 0.5,
            wasStreaming: false
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DirectAPIResult.self, from: data)

        #expect(decoded.success == false)
        #expect(decoded.error == "HTTP 401")
        #expect(decoded.statusCode == 401)
    }

    // MARK: - extractCookies Tests

    @Test("Extract cookies from HTTPCookie array")
    func testExtractCookies() {
        let cookies = [
            HTTPCookie(properties: [
                .name: "session",
                .value: "abc123",
                .domain: ".example.com",
                .path: "/"
            ])!,
            HTTPCookie(properties: [
                .name: "token",
                .value: "xyz789",
                .domain: ".example.com",
                .path: "/"
            ])!
        ]

        let header = DirectWebAPIClient.extractCookies(from: cookies)

        #expect(header.contains("session=abc123"))
        #expect(header.contains("token=xyz789"))
        #expect(header.contains("; "))
    }

    @Test("Extract cookies from empty array")
    func testExtractCookiesEmpty() {
        let header = DirectWebAPIClient.extractCookies(from: [])
        #expect(header.isEmpty)
    }

    // MARK: - convertCookies Tests

    @Test("Convert BrowserCookie to HTTPCookie")
    func testConvertCookies() {
        let browserCookies = [
            BrowserCookie(
                name: "session",
                value: "abc123",
                domain: ".example.com",
                path: "/",
                expiresEpoch: nil,
                httpOnly: true,
                secure: true
            )
        ]

        let httpCookies = DirectWebAPIClient.convertCookies(browserCookies)

        #expect(httpCookies.count == 1)
        #expect(httpCookies[0].name == "session")
        #expect(httpCookies[0].value == "abc123")
        #expect(httpCookies[0].domain == ".example.com")
    }

    @Test("Convert empty BrowserCookie array")
    func testConvertCookiesEmpty() {
        let httpCookies = DirectWebAPIClient.convertCookies([])
        #expect(httpCookies.isEmpty)
    }

    // MARK: - parseSSEEvent Tests

    @Test("Parse SSE event with all fields")
    func testParseSSEEventAllFields() {
        let raw = "event: message\ndata: {\"text\": \"Hello\"}\nid: evt_123\nretry: 5000\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.data == "{\"text\": \"Hello\"}")
        #expect(event?.id == "evt_123")
        #expect(event?.retry == 5000)
    }

    @Test("Parse SSE event with only data")
    func testParseSSEEventDataOnly() {
        let raw = "data: {\"text\": \"Hello\"}\n\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.data == "{\"text\": \"Hello\"}")
    }

    @Test("Parse SSE event returns nil for empty data")
    func testParseSSEEventEmptyData() {
        let raw = "event: message\n\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event == nil)
    }

    @Test("Parse SSE [DONE] event")
    func testParseSSEEventDone() {
        let raw = "data: [DONE]\n\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event != nil)
        #expect(event?.data == "[DONE]")
    }

    @Test("Parse SSE event with multiple data lines")
    func testParseSSEEventMultipleDataLines() {
        let raw = "data: {\"text\": \"Hello\"\ndata: \" world\"}\n\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event != nil)
        // Multi-line data joins with actual newline
        #expect(event?.data == "{\"text\": \"Hello\"\n\" world\"}")
    }

    // MARK: - extractToken Tests

    @Test("Extract Bearer token from headers")
    func testExtractBearerToken() {
        let headers = ["Authorization": "Bearer token123"]
        let token = DirectWebAPIClient.extractToken(from: headers)

        #expect(token == "token123")
    }

    @Test("Extract token from custom header")
    func testExtractCustomToken() {
        let headers = ["X-Auth-Token": "mytoken"]
        let token = DirectWebAPIClient.extractToken(from: headers, headerName: "X-Auth-Token")

        #expect(token == "mytoken")
    }

    @Test("Extract token returns nil when header missing")
    func testExtractTokenMissing() {
        let headers: [String: String] = [:]
        let token = DirectWebAPIClient.extractToken(from: headers)

        #expect(token == nil)
    }

    @Test("Extract token from cookies")
    func testExtractTokenFromCookies() {
        let cookies = [
            BrowserCookie(
                name: "session_token",
                value: "abc123",
                domain: ".example.com",
                path: "/",
                expiresEpoch: nil,
                httpOnly: false,
                secure: true
            )
        ]

        let token = DirectWebAPIClient.extractToken(from: cookies, tokenName: "session_token")

        #expect(token == "abc123")
    }

    @Test("Extract token from cookies returns nil when not found")
    func testExtractTokenFromCookiesNotFound() {
        let cookies = [
            BrowserCookie(
                name: "other_cookie",
                value: "abc123",
                domain: ".example.com",
                path: "/",
                expiresEpoch: nil,
                httpOnly: false,
                secure: true
            )
        ]

        let token = DirectWebAPIClient.extractToken(from: cookies, tokenName: "session_token")

        #expect(token == nil)
    }

    // MARK: - SSEEvent Tests

    @Test("SSEEvent encodes and decodes correctly")
    func testSSEEventCodable() throws {
        let event = SSEEvent(
            type: "message",
            data: "{\"text\": \"Hello\"}",
            id: "evt_123",
            retry: 5000
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SSEEvent.self, from: data)

        #expect(decoded.type == "message")
        #expect(decoded.data == "{\"text\": \"Hello\"}")
        #expect(decoded.id == "evt_123")
        #expect(decoded.retry == 5000)
    }

    @Test("SSEEvent handles nil optional fields")
    func testSSEEventOptionals() throws {
        let event = SSEEvent(
            type: "message",
            data: "Hello",
            id: nil,
            retry: nil
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SSEEvent.self, from: data)

        #expect(decoded.id == nil)
        #expect(decoded.retry == nil)
    }

    // MARK: - Edge Cases

    @Test("Extract cookies handles special characters in values")
    func testExtractCookiesSpecialChars() {
        let cookies = [
            HTTPCookie(properties: [
                .name: "session",
                .value: "abc=123;def=456",
                .domain: ".example.com",
                .path: "/"
            ])!
        ]

        let header = DirectWebAPIClient.extractCookies(from: cookies)

        #expect(header.contains("session=abc=123;def=456"))
    }

    @Test("Parse SSE event handles malformed data")
    func testParseSSEEventMalformed() {
        let raw = "not a valid sse event"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event == nil)
    }

    @Test("Extract Bearer token handles malformed header")
    func testExtractBearerTokenMalformed() {
        let headers = ["Authorization": "Bearer"]
        let token = DirectWebAPIClient.extractToken(from: headers)

        // "Bearer" without space returns "Bearer" as-is (no prefix to strip)
        #expect(token == "Bearer")
    }
}
