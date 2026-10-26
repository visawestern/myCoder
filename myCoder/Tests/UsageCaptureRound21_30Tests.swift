import Testing
import Foundation
@testable import myCoder

@Suite("Usage pipeline edge cases (rounds 21-30)")
struct UsageEdgeCaseTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "s1", projectId: "p1", title: "t", directory: "/tmp")
        return db
    }

    // 21: nil usage -> no point
    @Test func nilUsageYieldsNoDataPoint() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x", usage: nil)
        #expect(try db.usageDataPoints().isEmpty)
    }

    // 22: zero tokens -> no point (avoid polluting aggregates)
    @Test func zeroTokensYieldsNoDataPoint() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 0, completionTokens: 0, costUSD: nil, modelID: "m", providerID: "p"))
        #expect(try db.usageDataPoints().isEmpty)
    }

    // 23: cost nil vs 0.0 distinct
    @Test func nilCostDistinctFromZeroCost() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p"))
        try db.insertMessage(id: "b", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.0, modelID: "m", providerID: "p"))
        let aggs = UsageStatisticsAggregator.aggregateByModel(try db.usageDataPoints())
        #expect(aggs.first?.costUSD == 0.0)
    }

    // 24: large Int64 token counts without overflow
    @Test func largeTokenCountsNoOverflow() throws {
        let db = try makeDB()
        let big = 1_000_000_000
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: big, completionTokens: big, costUSD: nil, modelID: "m", providerID: "p"))
        let points = try db.usageDataPoints()
        #expect(points.first?.totalTokens == 2_000_000_000)
    }

    // 25: unknown model/provider defaults
    @Test func emptyModelProviderDefaultToUnknown() throws {
        let c = UsageCapture(promptTokens: 1, completionTokens: 1, costUSD: nil, modelID: "", providerID: "")
        #expect(c.modelID == "unknown")
        #expect(c.providerID == "unknown")
    }

    // 26: user messages ignored for usage points
    @Test func userMessagesNotCountedInUsagePoints() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "q",
            usage: UsageCapture(promptTokens: 999, completionTokens: 999, costUSD: nil, modelID: "m", providerID: "p"))
        #expect(try db.usageDataPoints().isEmpty)
    }

    // 27: updateTokens overwrites previous
    @Test func updateTokensOverwritesAndReaggregates() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "old", providerID: "p"))
        try db.updateMessageTokens(id: "m1",
            usage: UsageCapture(promptTokens: 1000, completionTokens: 500, costUSD: 0.1, modelID: "new", providerID: "p"))
        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.totalTokens == 1500)
        #expect(points.first?.costUSD == 0.1)
        let session = try #require(try db.getSessionsByProject(projectId: "p1").first)
        #expect(session.tokensUsed == 1500)
        #expect(session.costUsd == 0.1)
    }

    // 28: updateTokens on missing message is safe noop
    @Test func updateTokensMissingMessageIsNoop() throws {
        let db = try makeDB()
        #expect(try db.updateMessageTokens(id: "ghost",
            usage: UsageCapture(promptTokens: 1, completionTokens: 1, costUSD: nil, modelID: "m", providerID: "p")) == false)
        #expect(try db.usageDataPoints().isEmpty)
    }

    // 29: multiple messages in one session aggregate correctly
    @Test func multiMessageSessionAggregation() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "m", providerID: "p"))
        try db.insertMessage(id: "b", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 200, completionTokens: 100, costUSD: 0.02, modelID: "m", providerID: "p"))
        try db.insertMessage(id: "c", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 300, completionTokens: 150, costUSD: nil, modelID: "m", providerID: "p"))
        let session = try #require(try db.getSessionsByProject(projectId: "p1").first)
        #expect(session.tokensUsed == 900)
        #expect(session.costUsd == 0.03)
    }

    // 30: aggregator costLabel edge values
    @Test func costLabelEdgeValues() {
        #expect(UsageStatisticsAggregator.costLabel(nil) == "N/A")
        #expect(UsageStatisticsAggregator.costLabel(0.0) == "$0.00")
        #expect(UsageStatisticsAggregator.costLabel(0.005) == "$0.01")
        #expect(UsageStatisticsAggregator.costLabel(1234.567) == "$1234.57")
    }
}
