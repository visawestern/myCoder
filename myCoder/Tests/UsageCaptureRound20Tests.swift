import Testing
import Foundation
@testable import myCoder

@Suite("Full usage pipeline integration (round 20)")
struct UsagePipelineIntegrationTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "sess", projectId: "proj", title: "Chat", directory: "/tmp")
        return db
    }

    /// ACP-style flow: response usage -> DB -> usageDataPoints -> aggregate
    @Test func acpPipelineEndToEnd() throws {
        let db = try makeDB()

        let acpResponse = """
        {"id":"abc","object":"chat.completion","created":1700000000,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":250,"completion_tokens":100,"total_tokens":350}}
        """
        let resp = try JSONDecoder().decode(ACPChatResponse.self, from: acpResponse.data(using: .utf8)!)
        let usage = UsageCapture(acpUsage: resp.usage!, modelID: resp.model, providerID: "openai")

        try db.insertMessage(id: "m1", sessionId: "sess", role: "assistant", content: "done", usage: usage)

        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.promptTokens == 250)
        #expect(points.first?.completionTokens == 100)
        #expect(points.first?.model == "gpt-4o")
        #expect(points.first?.provider == "openai")

        let aggs = UsageStatisticsAggregator.aggregateByModel(points)
        #expect(aggs.count == 1)
        #expect(aggs.first?.totalTokens == 350)
        #expect(aggs.first?.messageCount == 1)
        #expect(aggs.first?.costUSD == nil)
        #expect(UsageStatisticsAggregator.costLabel(aggs.first?.costUSD) == "N/A")

        let session = try #require(try db.getSessionsByProject(projectId: "proj").first)
        #expect(session.tokensUsed == 350)
    }

    /// Direct-chat flow with cost.
    @Test func directPipelineEndToEndWithCost() throws {
        let db = try makeDB()
        let usage = UsageCapture(promptTokens: 500, completionTokens: 200, costUSD: 0.07, modelID: "claude-3.5", providerID: "anthropic")
        try db.insertMessage(id: "m1", sessionId: "sess", role: "assistant", content: "hi", usage: usage)

        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        let aggs = UsageStatisticsAggregator.aggregateByModel(points)
        #expect(aggs.first?.costUSD == 0.07)
        #expect(UsageStatisticsAggregator.costLabel(aggs.first?.costUSD) == "$0.07")

        let session = try #require(try db.getSessionsByProject(projectId: "proj").first)
        #expect(session.tokensUsed == 700)
        #expect(session.costUsd == 0.07)
    }

    /// nil usage (web-chat / SSE) produces no data point, no crash.
    @Test func nilUsageProducesNoDataPoint() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "sess", role: "assistant", content: "web answer", usage: nil)
        #expect(try db.usageDataPoints().isEmpty)
        let session = try #require(try db.getSessionsByProject(projectId: "proj").first)
        #expect(session.tokensUsed == 0)
        #expect(session.costUsd == 0.0)
    }

    /// Mixed cost (one nil, one set) aggregates only the present cost.
    @Test func mixedCostAggregatesPresentOnly() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "sess", role: "assistant", content: "local",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: nil, modelID: "qwen", providerID: "ollama"))
        try db.insertMessage(id: "b", sessionId: "sess", role: "assistant", content: "paid",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.02, modelID: "gpt-4o", providerID: "openai"))

        let aggs = UsageStatisticsAggregator.aggregateByModel(try db.usageDataPoints())
        #expect(aggs.count == 2)
        let total = UsageStatisticsAggregator.totals(try db.usageDataPoints())
        #expect(total.tokens == 300)
        #expect(total.cost == 0.02)
    }
}
