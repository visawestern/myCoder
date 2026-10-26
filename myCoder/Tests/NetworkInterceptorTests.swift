import Testing
import Foundation
@testable import myCoder

@Suite("NetworkInterceptor Tests")
struct NetworkInterceptorTests {

    // MARK: - CapturedRequest Tests

    @Test("CapturedRequest encodes and decodes correctly")
    func testCapturedRequestCodable() throws {
        let request = CapturedRequest(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: "{\"message\": \"Hello\"}",
            timestamp: Date(),
            requestID: "req_123"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CapturedRequest.self, from: data)

        #expect(decoded.url == "https://api.kimi.com/chat")
        #expect(decoded.method == "POST")
        #expect(decoded.headers["Content-Type"] == "application/json")
        #expect(decoded.body == "{\"message\": \"Hello\"}")
        #expect(decoded.requestID == "req_123")
    }

    @Test("CapturedRequest handles nil body")
    func testCapturedRequestNilBody() throws {
        let request = CapturedRequest(
            url: "https://api.kimi.com/chat",
            method: "GET",
            headers: [:],
            body: nil,
            timestamp: Date(),
            requestID: "req_456"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CapturedRequest.self, from: data)

        #expect(decoded.body == nil)
    }

    // MARK: - CapturedResponse Tests

    @Test("CapturedResponse encodes and decodes correctly")
    func testCapturedResponseCodable() throws {
        let response = CapturedResponse(
            url: "https://api.kimi.com/chat",
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: "{\"choices\": []}",
            requestID: "req_123",
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CapturedResponse.self, from: data)

        #expect(decoded.status == 200)
        #expect(decoded.requestID == "req_123")
    }

    // MARK: - ChatAPIEndpoint Tests

    @Test("ChatAPIEndpoint encodes and decodes correctly")
    func testChatAPIEndpointCodable() throws {
        let endpoint = ChatAPIEndpoint(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            bodyTemplate: "{\"message\": \"{{message}}\"}",
            isStreaming: true,
            contentType: "application/json",
            authLocation: "Authorization",
            authToken: "token123"
        )

        let data = try JSONEncoder().encode(endpoint)
        let decoded = try JSONDecoder().decode(ChatAPIEndpoint.self, from: data)

        #expect(decoded.url == "https://api.kimi.com/chat")
        #expect(decoded.isStreaming == true)
        #expect(decoded.authToken == "token123")
    }

    // MARK: - SSEEvent Tests

    @Test("SSEEvent encodes and decodes correctly")
    func testSSEEventCodable() throws {
        let event = SSEEvent(
            type: "message",
            data: "{\"choices\": []}",
            id: "evt_123",
            retry: 5000
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SSEEvent.self, from: data)

        #expect(decoded.type == "message")
        #expect(decoded.id == "evt_123")
        #expect(decoded.retry == 5000)
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

    @Test("Parse SSE event with multiple data lines")
    func testParseSSEEventMultipleDataLines() {
        let raw = "data: {\"text\": \"Hello\"\ndata: \" world\"}\n\n"
        let event = DirectWebAPIClient.parseSSEEvent(raw)

        #expect(event != nil)
        // Multi-line data joins with actual newline
        #expect(event?.data == "{\"text\": \"Hello\"\n\" world\"}")
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

    // MARK: - findChatAPI Tests

    @Test("Find chat API from POST requests with JSON body")
    func testFindChatAPIPostJSON() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/chat/send",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: "{\"message\": \"Hello\"}",
                timestamp: Date(),
                requestID: "req_1"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint != nil)
        #expect(endpoint?.url == "https://api.kimi.com/chat/send")
        #expect(endpoint?.method == "POST")
    }

    @Test("Find chat API with auth token")
    func testFindChatAPIWithAuth() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/chat",
                method: "POST",
                headers: [
                    "Content-Type": "application/json",
                    "Authorization": "Bearer token123"
                ],
                body: "{\"content\": \"Hello\"}",
                timestamp: Date(),
                requestID: "req_1"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint != nil)
        #expect(endpoint?.authToken == "token123")
        #expect(endpoint?.authLocation == "Authorization")
    }

    @Test("Find chat API with streaming")
    func testFindChatAPIStreaming() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/chat",
                method: "POST",
                headers: [
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream"
                ],
                body: "{\"prompt\": \"Hello\"}",
                timestamp: Date(),
                requestID: "req_1"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint != nil)
        #expect(endpoint?.isStreaming == true)
    }

    @Test("Find chat API ignores GET requests")
    func testFindChatAPIIgnoresGET() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/chat",
                method: "GET",
                headers: [:],
                body: nil,
                timestamp: Date(),
                requestID: "req_1"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint == nil)
    }

    @Test("Find chat API ignores non-JSON requests")
    func testFindChatAPIIgnoresNonJSON() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/chat",
                method: "POST",
                headers: ["Content-Type": "text/plain"],
                body: "Hello",
                timestamp: Date(),
                requestID: "req_1"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint == nil)
    }

    @Test("Find chat API from multiple requests")
    func testFindChatAPIMultiple() {
        let requests = [
            CapturedRequest(
                url: "https://api.kimi.com/auth",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: "{\"token\": \"abc\"}",
                timestamp: Date(),
                requestID: "req_1"
            ),
            CapturedRequest(
                url: "https://api.kimi.com/chat/send",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: "{\"message\": \"Hello\"}",
                timestamp: Date(),
                requestID: "req_2"
            )
        ]

        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint != nil)
        #expect(endpoint?.url == "https://api.kimi.com/chat/send")
    }

    // MARK: - buildDirectRequest Tests

    @Test("Build direct request with all fields")
    func testBuildDirectRequest() {
        let endpoint = ChatAPIEndpoint(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: ["Content-Type": "application/json", "X-Custom": "value"],
            bodyTemplate: "{\"message\": \"{{message}}\"}",
            isStreaming: false,
            contentType: "application/json",
            authLocation: "Authorization",
            authToken: "token123"
        )

        let cookies = [
            BrowserCookie(
                name: "session", value: "abc123",
                domain: ".kimi.com", path: "/",
                expiresEpoch: nil, httpOnly: true, secure: true
            )
        ]

        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: cookies, message: "Hello!"
        )

        #expect(request.url?.absoluteString == "https://api.kimi.com/chat")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session=abc123") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Build direct request replaces message placeholder")
    func testBuildDirectRequestMessagePlaceholder() {
        let endpoint = ChatAPIEndpoint(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: [:],
            bodyTemplate: "{\"message\": \"{{message}}\"}",
            isStreaming: false,
            contentType: "application/json",
            authLocation: nil,
            authToken: nil
        )

        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: [], message: "Test message"
        )

        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("Test message"))
    }

    @Test("Build direct request sets timeout")
    func testBuildDirectRequestTimeout() {
        let endpoint = ChatAPIEndpoint(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: [:],
            bodyTemplate: "{}",
            isStreaming: false,
            contentType: "application/json",
            authLocation: nil,
            authToken: nil
        )

        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: [], message: "Hello"
        )

        #expect(request.timeoutInterval == 60)
    }
}
