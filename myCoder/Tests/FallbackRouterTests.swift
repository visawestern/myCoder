import Testing
import Foundation
@testable import myCoder

@Suite("FallbackRouter Tests", .serialized)
struct FallbackRouterTests {

    // MARK: - SmartSendRoute Tests

    @Test("SmartSendRoute equality works correctly")
    func testSendRouteEquality() {
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

        let route1 = SmartSendRoute.directAPI(endpoint)
        let route2 = SmartSendRoute.directAPI(endpoint)
        let route3 = SmartSendRoute.smartElement(".send-btn", .sendButton)
        let route4 = SmartSendRoute.smartElement(".send-btn", .sendButton)
        let route5 = SmartSendRoute.browserAutomation
        let route6 = SmartSendRoute.browserAutomation
        let route7 = SmartSendRoute.none

        #expect(route1 == route2)
        #expect(route3 == route4)
        #expect(route5 == route6)
        #expect(route7 == .none)
        #expect(route1 != route3)
        #expect(route3 != route5)
    }

    // MARK: - SendAttempt Tests

    @Test("SendAttempt encodes and decodes correctly")
    func testSendAttemptCodable() throws {
        let attempt = SendAttempt(
            method: "directAPI",
            success: true,
            duration: 1.5,
            error: nil,
            response: "Hello!",
            confidence: 0.9
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(SendAttempt.self, from: data)

        #expect(decoded.method == "directAPI")
        #expect(decoded.success == true)
        #expect(decoded.duration == 1.5)
        #expect(decoded.response == "Hello!")
        #expect(decoded.confidence == 0.9)
    }

    @Test("SendAttempt handles error case")
    func testSendAttemptError() throws {
        let attempt = SendAttempt(
            method: "smartElement",
            success: false,
            duration: 0.5,
            error: "Element not found",
            response: nil,
            confidence: 0.0
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(SendAttempt.self, from: data)

        #expect(decoded.success == false)
        #expect(decoded.error == "Element not found")
        #expect(decoded.confidence == 0.0)
    }

    // MARK: - SendResult Tests

    @Test("SendResult encodes and decodes correctly")
    func testSendResultCodable() throws {
        let attempt = SendAttempt(
            method: "directAPI",
            success: true,
            duration: 1.0,
            error: nil,
            response: "Hi",
            confidence: 0.9
        )

        let result = SendResult(
            success: true,
            response: "Hi",
            attempts: [attempt],
            winningMethod: "directAPI",
            duration: 1.0
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SendResult.self, from: data)

        #expect(decoded.success == true)
        #expect(decoded.winningMethod == "directAPI")
        #expect(decoded.attempts.count == 1)
    }

    // MARK: - EndpointUpdate Tests

    @Test("EndpointUpdate encodes and decodes correctly")
    func testEndpointUpdateCodable() throws {
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

        let update = EndpointUpdate(
            endpoint: endpoint,
            reason: "Token expired",
            confidence: 0.8
        )

        let data = try JSONEncoder().encode(update)
        let decoded = try JSONDecoder().decode(EndpointUpdate.self, from: data)

        #expect(decoded.reason == "Token expired")
        #expect(decoded.confidence == 0.8)
    }

    // MARK: - Circuit Breaker Tests

    @Test("Circuit breaker opens after threshold failures")
    func testCircuitBreakerOpens() {
        // Reset state
        FallbackRouter.resetCircuitBreaker(method: "testMethod")

        // Record failures
        for _ in 0..<FallbackRouter.circuitBreakerThreshold {
            FallbackRouter.recordAttemptForTesting(method: "testMethod", success: false)
        }

        #expect(FallbackRouter.isCircuitOpenForTesting(method: "testMethod"))

        // Cleanup
        FallbackRouter.resetCircuitBreaker(method: "testMethod")
    }

    @Test("Circuit breaker resets on success")
    func testCircuitBreakerResets() {
        // Reset state
        FallbackRouter.resetCircuitBreaker(method: "testMethod2")

        // Record failures
        for _ in 0..<(FallbackRouter.circuitBreakerThreshold - 1) {
            FallbackRouter.recordAttemptForTesting(method: "testMethod2", success: false)
        }

        #expect(!FallbackRouter.isCircuitOpenForTesting(method: "testMethod2"))

        // Record success
        FallbackRouter.recordAttemptForTesting(method: "testMethod2", success: true)

        #expect(!FallbackRouter.isCircuitOpenForTesting(method: "testMethod2"))

        // Cleanup
        FallbackRouter.resetCircuitBreaker(method: "testMethod2")
    }

    @Test("Circuit breaker resets after cooldown")
    func testCircuitBreakerCooldown() {
        // Reset state
        FallbackRouter.resetCircuitBreaker(method: "testMethod3")

        // Record failures to open circuit
        for _ in 0..<FallbackRouter.circuitBreakerThreshold {
            FallbackRouter.recordAttemptForTesting(method: "testMethod3", success: false)
        }

        #expect(FallbackRouter.isCircuitOpenForTesting(method: "testMethod3"))

        // Wait for cooldown (simulate by setting last failure time far in the past)
        FallbackRouter.setLastFailureTimeForTesting(method: "testMethod3", time: Date().addingTimeInterval(-FallbackRouter.circuitBreakerCooldown - 1))

        #expect(!FallbackRouter.isCircuitOpenForTesting(method: "testMethod3"))

        // Cleanup
        FallbackRouter.resetCircuitBreaker(method: "testMethod3")
    }

    // MARK: - learnFromFailure Tests

    @Test("Learn from 401 Unauthorized")
    func testLearnFrom401() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "HTTP 401 Unauthorized",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("Token expired") == true)
        #expect(update?.confidence == 0.8)
    }

    @Test("Learn from 403 Forbidden")
    func testLearnFrom403() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "HTTP 403 Forbidden",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("CSRF") == true)
        #expect(update?.confidence == 0.7)
    }

    @Test("Learn from 429 Too Many Requests")
    func testLearnFrom429() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "HTTP 429 Too Many Requests",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("Rate limited") == true)
        #expect(update?.confidence == 0.9)
    }

    @Test("Learn from 404 Not Found")
    func testLearnFrom404() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "HTTP 404 Not Found",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("Endpoint changed") == true)
    }

    @Test("Learn from 500 Server Error")
    func testLearnFrom500() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "HTTP 500 Internal Server Error",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("Server error") == true)
    }

    @Test("Learn from network error")
    func testLearnFromNetworkError() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "Network error: Connection timed out",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update != nil)
        #expect(update?.reason.contains("Network error") == true)
    }

    @Test("Learn returns nil for unknown error")
    func testLearnFromUnknownError() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: false,
            duration: 1.0,
            error: "Something unknown happened",
            response: nil,
            confidence: 0.0
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update == nil)
    }

    @Test("Learn returns nil for success")
    func testLearnFromSuccess() {
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

        let attempt = SendAttempt(
            method: "directAPI",
            success: true,
            duration: 1.0,
            error: nil,
            response: "Hello!",
            confidence: 0.9
        )

        let update = SmartSend.learnFromFailure(attempt: attempt, endpoint: endpoint)

        #expect(update == nil)
    }
}
