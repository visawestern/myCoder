import Testing
import Foundation
@testable import myCoder

@Suite("Harness-tax turn accounting C1 (eval harness-tax)")
struct UsageHarnessProfileTests {

    @Test func profileDefaultsToUnknown() {
        let c = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.01,
                             modelID: "m", providerID: "p")
        #expect(c.profile == .unknown)
        #expect(c.contextBytes == 0)
    }

    @Test func contextBytesClamped() {
        let c = UsageCapture(promptTokens: 1, completionTokens: 1, costUSD: nil,
                             modelID: "m", providerID: "p", profile: .full,
                             contextBytes: -50)
        #expect(c.contextBytes == 0)
        #expect(c.profile == .full)
    }

    @Test func dataPointCarriesProfile() {
        let p = UsageDataPoint(timestamp: Date(), model: "m", provider: "p",
                               promptTokens: 3, completionTokens: 2, costUSD: nil,
                               profile: .minimal, contextBytes: 1200)
        #expect(p.profile == .minimal)
        #expect(p.contextBytes == 1200)
    }

    @Test func aggregateByProfileGroups() {
        let now = Date()
        let points = [
            UsageDataPoint(timestamp: now, model: "m", provider: "p",
                           promptTokens: 100, completionTokens: 10, costUSD: 0.02,
                           profile: .full, contextBytes: 5000),
            UsageDataPoint(timestamp: now, model: "m", provider: "p",
                           promptTokens: 50, completionTokens: 5, costUSD: 0.01,
                           profile: .full, contextBytes: 4000),
            UsageDataPoint(timestamp: now, model: "m", provider: "p",
                           promptTokens: 20, completionTokens: 2, costUSD: 0.005,
                           profile: .minimal, contextBytes: 800),
        ]
        let aggs = UsageStatisticsAggregator.aggregateByProfile(points)
        #expect(aggs.count == 2)
        let full = aggs.first { $0.key == "full" }
        let minimal = aggs.first { $0.key == "minimal" }
        #expect(full?.messageCount == 2)
        #expect(full?.promptTokens == 150)
        #expect(minimal?.messageCount == 1)
        #expect(minimal?.promptTokens == 20)
    }

    @Test func historyBuilderContextBytes() {
        let sys = "system-preamble"
        let prior = [ChatHistoryBuilder.Turn(role: "user", content: "hello", isFinished: true)]
        let bytes = ChatHistoryBuilder.contextBytes(systemPrompt: sys, priorTurns: prior, userText: "hi")
        #expect(bytes > 0)
        #expect(bytes == (sys + "hello" + "hi").utf8.count)
    }

    @Test func sendAttachesContextBytes() async throws {
        let body = """
        {"id":"x","object":"chat.completion","created":1,"model":"m",
         "choices":[{"index":0,"message":{"role":"assistant","content":"yo"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":10,"completion_tokens":2}}
        """.data(using: .utf8)!
        let transport = MockDirectChatTransport(response: (200, body))
        let msgs = [DirectChatMessage(role: "system", content: "sys-preamble"),
                    DirectChatMessage(role: "user", content: "hello world")]
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "m",
            messages: msgs, transport: transport)
        let usage = try #require(result.usage)
        #expect(usage.contextBytes == ("sys-preamble" + "hello world").utf8.count)
        #expect(usage.profile == .unknown)
    }
}
