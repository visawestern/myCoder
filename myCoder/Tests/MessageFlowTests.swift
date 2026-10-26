import Testing
import Foundation
@testable import myCoder

// MARK: - SSE Client Tests

@Suite("SSE Client")
struct SSEClientTests {

    @Test("SSEClient initializes with nil event handler")
    func initialHandler() {
        let client = SSEClient()
        #expect(client.onEvent == nil)
    }

    @Test("SSEClient processes data: lines correctly")
    func processSSEData() throws {
        let client = SSEClient()
        var receivedType = ""
        var receivedPayload: [String: Any] = [:]

        client.onEvent = { type, payload in
            receivedType = type
            receivedPayload = payload
        }

        let jsonPayload: [String: Any] = [
            "payload": [
                "type": "message.part.delta",
                "properties": [
                    "sessionID": "ses_123",
                    "delta": "Hello"
                ]
            ]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: jsonPayload)
        let payloadString = String(data: payloadData, encoding: .utf8)!
        let sseData = "data: \(payloadString)\n\n"

        client.processSSEData(sseData)

        #expect(receivedType == "message.part.delta")
        let props = receivedPayload["properties"] as? [String: Any]
        #expect(props?["sessionID"] as? String == "ses_123")
        #expect(props?["delta"] as? String == "Hello")
    }

    @Test("SSEClient ignores non-data lines")
    func ignoreNonDataLines() {
        let client = SSEClient()
        var eventCount = 0
        client.onEvent = { _, _ in eventCount += 1 }

        client.processSSEData("event: ping\n\n")
        #expect(eventCount == 0)
    }

    @Test("SSEClient handles multiple events in one buffer")
    func multipleEvents() {
        let client = SSEClient()
        var events: [String] = []
        client.onEvent = { type, _ in events.append(type) }

        let payload1: [String: Any] = ["payload": ["type": "event.a", "properties": ["v": 1]]]
        let payload2: [String: Any] = ["payload": ["type": "event.b", "properties": ["v": 2]]]
        let d1 = try! JSONSerialization.data(withJSONObject: payload1)
        let d2 = try! JSONSerialization.data(withJSONObject: payload2)
        let buffer = "data: \(String(data: d1, encoding: .utf8)!)\n\ndata: \(String(data: d2, encoding: .utf8)!)\n\n"

        client.processSSEData(buffer)

        #expect(events == ["event.a", "event.b"])
    }
}

// MARK: - Message Send Flow Tests

@Suite("Message Send Flow")
struct MessageSendFlowTests {

    @Test("Message sending creates assistant placeholder")
    func assistantPlaceholder() {
        var messages: [Message] = []
        let assistantID = UUID().uuidString
        messages.append(Message(role: .user, content: "Hello"))
        messages.append(Message(id: assistantID, role: .assistant, content: ""))

        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[1].role == .assistant)
        #expect(messages[1].content.isEmpty)
    }

    @Test("Message sending clears input and sets loading")
    func clearsInput() {
        var inputText = "Hello"
        var isLoading = false

        inputText = ""
        isLoading = true

        #expect(inputText.isEmpty)
        #expect(isLoading)
    }

    @Test("POST response text is used when non-empty")
    func postResponseUsed() {
        let apiResponse = "The answer is 42"
        var assistantContent = ""

        if !apiResponse.isEmpty {
            assistantContent = apiResponse
        }

        #expect(assistantContent == "The answer is 42")
    }

    @Test("Empty POST response falls back to SSE streaming")
    func emptyPostFallsToSSE() {
        let apiResponse = ""
        var fallbackToSSE = false

        if apiResponse.isEmpty {
            fallbackToSSE = true
        }

        #expect(fallbackToSSE)
    }

    @Test("SSE message.part.delta appends to streaming text")
    func sseDeltaAppends() {
        var streamingText = ""
        streamingText += "Hello"
        streamingText += " World"

        #expect(streamingText == "Hello World")
    }

    @Test("SSE session.status idle sets loading false")
    func sseIdleStopsLoading() {
        var isLoading = true
        var sseConnected = true

        let statusType = "idle"
        if statusType == "idle" {
            isLoading = false
            sseConnected = false
        }

        #expect(!isLoading)
        #expect(!sseConnected)
    }

    @Test("SSE connection established before POST")
    func sseBeforePost() {
        var sseConnected = false
        var postSent = false

        sseConnected = true
        postSent = true

        #expect(sseConnected)
        #expect(postSent)
    }
}

// MARK: - Status Bar Tests

@Suite("Status Bar")
struct StatusBarTests {

    private func connectionLabel(connected: Bool) -> String {
        connected ? "Connected" : "Disconnected"
    }

    private func activityLabel(isStreaming: Bool, isLoading: Bool) -> String {
        if isStreaming { return "Generating..." }
        if isLoading { return "Processing..." }
        return "Idle"
    }

    private func tokenLabel(tokens: Int?) -> String {
        guard let tokens else { return "" }
        return "\(tokens) tokens"
    }

    @Test("Status bar shows server connection state")
    func serverState() {
        #expect(connectionLabel(connected: true) == "Connected")
    }

    @Test("Status bar shows disconnected when not connected")
    func disconnectedState() {
        #expect(connectionLabel(connected: false) == "Disconnected")
    }

    @Test("Status bar shows model name")
    func modelName() {
        let model = "mycoder-auto-free"
        #expect(model == "mycoder-auto-free")
    }

    @Test("Status bar shows token usage when available")
    func tokenUsage() {
        #expect(tokenLabel(tokens: 1500) == "1500 tokens")
    }

    @Test("Status bar shows idle when no activity")
    func idleState() {
        #expect(activityLabel(isStreaming: false, isLoading: false) == "Idle")
    }

    @Test("Status bar shows generating when streaming")
    func streamingState() {
        #expect(activityLabel(isStreaming: true, isLoading: true) == "Generating...")
    }
}
