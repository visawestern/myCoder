import Testing
import Foundation
@testable import myCoder

@Suite("Session tokens_used / cost_usd aggregation (round 15)")
struct SessionUsageAggregationTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "s1", projectId: "p1", title: "t", directory: "/tmp")
        return db
    }

    private func session(_ db: DatabaseManager) throws -> SessionRecord {
        let list = try db.getSessionsByProject(projectId: "p1")
        return try #require(list.first)
    }

    @Test func sessionTokensUsedSumsMessageTokens() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "a",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "gpt-4o", providerID: "openai"))
        try db.insertMessage(id: "m2", sessionId: "s1", role: "assistant", content: "b",
            usage: UsageCapture(promptTokens: 200, completionTokens: 100, costUSD: 0.02, modelID: "gpt-4o", providerID: "openai"))

        #expect(try session(db).tokensUsed == 450)
    }

    @Test func sessionCostUsdAccumulatesWhenPresent() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "a",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "m", providerID: "p"))
        try db.insertMessage(id: "m2", sessionId: "s1", role: "assistant", content: "b",
            usage: UsageCapture(promptTokens: 200, completionTokens: 100, costUSD: 0.02, modelID: "m", providerID: "p"))
        #expect(try session(db).costUsd == 0.03)
    }

    @Test func sessionWithNoUsageMessagesHasZeroTokens() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "hi")
        #expect(try session(db).tokensUsed == 0)
        #expect(try session(db).costUsd == 0.0)
    }

    @Test func updateTokensReflectedInSessionAggregation() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "…")
        #expect(try session(db).tokensUsed == 0)
        try db.updateMessageTokens(id: "m1",
            usage: UsageCapture(promptTokens: 300, completionTokens: 150, costUSD: 0.05, modelID: "claude", providerID: "anthropic"))
        #expect(try session(db).tokensUsed == 450)
        #expect(try session(db).costUsd == 0.05)
    }
}
