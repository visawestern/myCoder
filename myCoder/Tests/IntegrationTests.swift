import Testing
import Foundation
@testable import myCoder

@Suite("Integration Tests - Smart Send Flow")
struct IntegrationTests {

    // MARK: - Full Flow Tests

    @Test("Full smart send flow: all components integrate correctly")
    func testFullFlowIntegration() throws {
        // 1. Create mock endpoint
        let endpoint = ChatAPIEndpoint(
            url: "https://api.kimi.com/chat/send",
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer test_token"
            ],
            bodyTemplate: "{\"message\": \"{{message}}\"}",
            isStreaming: false,
            contentType: "application/json",
            authLocation: "Authorization",
            authToken: "test_token"
        )

        // 2. Create mock cookies
        let cookies = [
            BrowserCookie(
                name: "session",
                value: "abc123",
                domain: ".kimi.com",
                path: "/",
                expiresEpoch: nil,
                httpOnly: true,
                secure: true
            )
        ]

        // 3. Build request
        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: cookies, message: "Hello!"
        )

        // 4. Verify request
        #expect(request.url?.absoluteString == "https://api.kimi.com/chat/send")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test_token")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session=abc123") == true)

        // 5. Verify body
        let body = String(data: request.httpBody!, encoding: .utf8)!
        #expect(body.contains("Hello!"))
    }

    @Test("Smart element finder classifies all element types")
    func testSmartElementFinderAllTypes() {
        // Test each element type can be classified
        let testCases: [(ElementType, [String], String, String)] = [
            (.sendButton, ["send-btn"], "", ""),
            (.input, ["editor"], "", ""),
            (.modelDropdown, ["model-selector"], "", ""),
            (.newChat, ["new-chat-btn"], "", ""),
            (.effortToggle, ["effort-selector"], "", ""),
            (.loginButton, ["login-btn"], "", ""),
            (.logoutButton, ["logout-btn"], "", ""),
            (.profileButton, ["profile-btn"], "", ""),
            (.searchButton, ["search-btn"], "", ""),
            (.menuButton, ["menu-btn"], "", ""),
            (.settingsButton, ["settings-btn"], "", ""),
            (.shareButton, ["share-btn"], "", ""),
            (.copyButton, ["copy-btn"], "", ""),
            (.deleteButton, ["delete-btn"], "", ""),
            (.refreshButton, ["refresh-btn"], "", ""),
        ]

        for (expectedType, classes, ariaLabel, text) in testCases {
            let result = SmartElementFinder.classifyElement(
                tagName: "button",
                classes: classes,
                ariaLabel: ariaLabel,
                text: text,
                role: "",
                ariaHasPopup: "",
                inputType: "",
                placeholder: "",
                contentEditable: "",
                svgName: "",
                dataTestId: "",
                position: nil
            )
            #expect(result == expectedType, "Failed to classify \(expectedType): got \(result)")
        }
    }

    @Test("Network interceptor captures all request types")
    func testNetworkInterceptorCapture() {
        // Test that CapturedRequest can be created with various data
        let request1 = CapturedRequest(
            url: "https://api.kimi.com/chat",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: "{\"message\": \"Hello\"}",
            timestamp: Date(),
            requestID: "req_1"
        )

        let request2 = CapturedRequest(
            url: "https://api.kimi.com/auth",
            method: "GET",
            headers: [:],
            body: nil,
            timestamp: Date(),
            requestID: "req_2"
        )

        let requests = [request1, request2]

        // Find chat API
        let endpoint = NetworkInterceptor.findChatAPI(requests: requests)

        #expect(endpoint != nil)
        #expect(endpoint?.url == "https://api.kimi.com/chat")
    }

    @Test("SSE parsing handles real-world data")
    func testSSEParsingRealWorld() {
        let sseData = """
        event: message
        data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

        event: message
        data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

        event: message
        data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

        event: message
        data: [DONE]
        """

        let events = sseData.components(separatedBy: "\n\n").compactMap { DirectWebAPIClient.parseSSEEvent($0) }

        #expect(events.count == 4)
        #expect(events[0].type == "message")
        #expect(events[1].data.contains("Hello"))
        #expect(events[2].data.contains("world"))
        #expect(events[3].data == "[DONE]")
    }

    @Test("Cookie conversion preserves all fields")
    func testCookieConversionPreservesFields() {
        let browserCookies = [
            BrowserCookie(
                name: "session",
                value: "abc123",
                domain: ".kimi.com",
                path: "/",
                expiresEpoch: Date(timeIntervalSince1970: 1700000000).timeIntervalSince1970,
                httpOnly: true,
                secure: true
            ),
            BrowserCookie(
                name: "token",
                value: "xyz789",
                domain: ".kimi.com",
                path: "/api",
                expiresEpoch: nil,
                httpOnly: false,
                secure: false
            )
        ]

        let httpCookies = DirectWebAPIClient.convertCookies(browserCookies)

        #expect(httpCookies.count == 2)
        #expect(httpCookies[0].name == "session")
        #expect(httpCookies[0].value == "abc123")
        #expect(httpCookies[1].name == "token")
        #expect(httpCookies[1].value == "xyz789")
    }

    @Test("Endpoint update learning covers all HTTP errors")
    func testEndpointUpdateLearning() {
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

        let errorTests: [(String, String)] = [
            ("HTTP 401 Unauthorized", "Token expired"),
            ("HTTP 403 Forbidden", "CSRF"),
            ("HTTP 429 Too Many Requests", "Rate limited"),
            ("HTTP 404 Not Found", "Endpoint changed"),
            ("HTTP 500 Internal Server Error", "Server error"),
            ("Network error: Connection timed out", "Network error"),
        ]

        for (error, expectedReason) in errorTests {
            let attempt = SendAttempt(
                method: "directAPI",
                success: false,
                duration: 1.0,
                error: error,
                response: nil,
                confidence: 0.0
            )

            let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

            #expect(update != nil, "Failed to learn from error: \(error)")
            #expect(update?.reason.contains(expectedReason) == true,
                    "Wrong reason for \(error): got \(update?.reason ?? "nil"), expected \(expectedReason)")
        }
    }

    @Test("Circuit breaker prevents infinite retries")
    func testCircuitBreakerPreventsInfiniteRetries() {
        // Reset
        FallbackRouter.resetCircuitBreaker(method: "testInfinite")

        // Record enough failures to open circuit
        for _ in 0..<FallbackRouter.circuitBreakerThreshold {
            FallbackRouter.recordAttemptForTesting(method: "testInfinite", success: false)
        }

        #expect(FallbackRouter.isCircuitOpenForTesting(method: "testInfinite"))

        // Cleanup
        FallbackRouter.resetCircuitBreaker(method: "testInfinite")
    }

    @Test("All struct types are Codable and Equatable")
    func testAllStructsCodable() throws {
        // SmartElementResult
        let smartResult = SmartElementResult(
            selector: ".test", confidence: 0.5, method: "test",
            elementType: .sendButton, text: nil, ariaLabel: nil,
            classes: [], tagName: "button", isVisible: true,
            isEnabled: true, position: nil
        )
        let smartData = try JSONEncoder().encode(smartResult)
        let smartDecoded = try JSONDecoder().decode(SmartElementResult.self, from: smartData)
        #expect(smartResult == smartDecoded)

        // DOMAnalysis
        let element = ElementInfo(
            selector: ".test", tagName: "button", text: "",
            ariaLabel: "", classes: [], isVisible: true,
            isEnabled: true, position: nil,
            elementType: .sendButton, confidence: 0.5
        )
        let analysis = DOMAnalysis(buttons: [element], inputs: [], dropdowns: [], links: [], allInteractive: [element])
        let analysisData = try JSONEncoder().encode(analysis)
        let analysisDecoded = try JSONDecoder().decode(DOMAnalysis.self, from: analysisData)
        #expect(analysis == analysisDecoded)

        // CapturedRequest
        let capturedReq = CapturedRequest(
            url: "https://test.com", method: "POST",
            headers: [:], body: nil, timestamp: Date(), requestID: "1"
        )
        let capturedReqData = try JSONEncoder().encode(capturedReq)
        let capturedReqDecoded = try JSONDecoder().decode(CapturedRequest.self, from: capturedReqData)
        #expect(capturedReq == capturedReqDecoded)

        // CapturedResponse
        let capturedResp = CapturedResponse(
            url: "https://test.com", status: 200,
            headers: [:], body: nil, requestID: "1", timestamp: Date()
        )
        let capturedRespData = try JSONEncoder().encode(capturedResp)
        let capturedRespDecoded = try JSONDecoder().decode(CapturedResponse.self, from: capturedRespData)
        #expect(capturedResp == capturedRespDecoded)

        // ChatAPIEndpoint
        let chatEndpoint = ChatAPIEndpoint(
            url: "https://test.com", method: "POST",
            headers: [:], bodyTemplate: "{}",
            isStreaming: false, contentType: "application/json",
            authLocation: nil, authToken: nil
        )
        let endpointData = try JSONEncoder().encode(chatEndpoint)
        let endpointDecoded = try JSONDecoder().decode(ChatAPIEndpoint.self, from: endpointData)
        #expect(chatEndpoint == endpointDecoded)

        // SSEEvent
        let sseEvent = SSEEvent(type: "message", data: "Hello", id: nil, retry: nil)
        let sseData = try JSONEncoder().encode(sseEvent)
        let sseDecoded = try JSONDecoder().decode(SSEEvent.self, from: sseData)
        #expect(sseEvent == sseDecoded)

        // DirectAPIResult
        let directResult = DirectAPIResult(
            success: true, response: "Hello", error: nil,
            statusCode: 200, headers: [:], duration: 1.0, wasStreaming: false
        )
        let directData = try JSONEncoder().encode(directResult)
        let directDecoded = try JSONDecoder().decode(DirectAPIResult.self, from: directData)
        #expect(directResult == directDecoded)

        // SendAttempt
        let sendAttempt = SendAttempt(
            method: "test", success: true, duration: 1.0,
            error: nil, response: "Hello", confidence: 0.5
        )
        let attemptData = try JSONEncoder().encode(sendAttempt)
        let attemptDecoded = try JSONDecoder().decode(SendAttempt.self, from: attemptData)
        #expect(sendAttempt == attemptDecoded)

        // SendResult
        let sendResult = SendResult(
            success: true, response: "Hello",
            attempts: [sendAttempt], winningMethod: "test", duration: 1.0
        )
        let resultData = try JSONEncoder().encode(sendResult)
        let resultDecoded = try JSONDecoder().decode(SendResult.self, from: resultData)
        #expect(sendResult == resultDecoded)

        // EndpointUpdate
        let endpointUpdate = EndpointUpdate(
            endpoint: chatEndpoint, reason: "test", confidence: 0.5
        )
        let updateData = try JSONEncoder().encode(endpointUpdate)
        let updateDecoded = try JSONDecoder().decode(EndpointUpdate.self, from: updateData)
        #expect(endpointUpdate == updateDecoded)

        // SmartSendResult
        let smartSendResult = SmartSendResult(
            success: true, response: "Hello",
            winningMethod: "test", attempts: [sendAttempt],
            duration: 1.0, updates: [endpointUpdate]
        )
        let smartSendData = try JSONEncoder().encode(smartSendResult)
        let smartSendDecoded = try JSONDecoder().decode(SmartSendResult.self, from: smartSendData)
        #expect(smartSendResult == smartSendDecoded)
    }
}
