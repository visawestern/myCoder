import Testing
import Foundation
@testable import myCoder

@Suite("SmartSend Tests")
struct SmartSendTests {

    // MARK: - SmartSendResult Tests

    @Test("SmartSendResult encodes and decodes correctly")
    func testSmartSendResultCodable() throws {
        let attempt = SendAttempt(
            method: "directAPI",
            success: true,
            duration: 1.0,
            error: nil,
            response: "Hello!",
            confidence: 0.9
        )

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

        let result = SmartSendResult(
            success: true,
            response: "Hello!",
            winningMethod: "directAPI",
            attempts: [attempt],
            duration: 1.5,
            updates: [update]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SmartSendResult.self, from: data)

        #expect(decoded.success == true)
        #expect(decoded.response == "Hello!")
        #expect(decoded.winningMethod == "directAPI")
        #expect(decoded.attempts.count == 1)
        #expect(decoded.updates.count == 1)
        #expect(decoded.duration == 1.5)
    }

    @Test("SmartSendResult handles failure case")
    func testSmartSendResultFailure() throws {
        let result = SmartSendResult(
            success: false,
            response: nil,
            winningMethod: nil,
            attempts: [],
            duration: 0.5,
            updates: []
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SmartSendResult.self, from: data)

        #expect(decoded.success == false)
        #expect(decoded.response == nil)
        #expect(decoded.winningMethod == nil)
        #expect(decoded.attempts.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("SmartSendResult handles multiple attempts")
    func testSmartSendResultMultipleAttempts() throws {
        let attempts = [
            SendAttempt(method: "directAPI", success: false, duration: 1.0, error: "401", response: nil, confidence: 0.0),
            SendAttempt(method: "smartElement", success: false, duration: 0.5, error: "Not found", response: nil, confidence: 0.0),
            SendAttempt(method: "browserAutomation", success: true, duration: 2.0, error: nil, response: "OK", confidence: 0.5)
        ]

        let result = SmartSendResult(
            success: true,
            response: "OK",
            winningMethod: "browserAutomation",
            attempts: attempts,
            duration: 3.5,
            updates: []
        )

        #expect(result.attempts.count == 3)
        #expect(result.winningMethod == "browserAutomation")
        #expect(result.success == true)
    }

    @Test("SmartSendResult handles empty updates")
    func testSmartSendResultEmptyUpdates() throws {
        let result = SmartSendResult(
            success: false,
            response: nil,
            winningMethod: nil,
            attempts: [],
            duration: 0.0,
            updates: []
        )

        #expect(result.updates.isEmpty)
    }
}
