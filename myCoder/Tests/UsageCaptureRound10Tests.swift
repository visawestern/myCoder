import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseManager.updateMessageTokens (round 10)")
struct DatabaseManagerUpdateTokensTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "s1", projectId: "p1", title: "t", directory: "/tmp")
        return db
    }

    @Test func updateTokensOnExistingMessageWritesColumns() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "…")
        #expect(try db.usageDataPoints().isEmpty)

        let usage = UsageCapture(promptTokens: 500, completionTokens: 200, costUSD: 0.08, modelID: "claude", providerID: "anthropic")
        try db.updateMessageTokens(id: "m1", usage: usage)

        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.promptTokens == 500)
        #expect(points.first?.completionTokens == 200)
        #expect(points.first?.model == "claude")
        #expect(points.first?.provider == "anthropic")
    }

    @Test func updateTokensOnMissingMessageIsNoop() throws {
        let db = try makeDB()
        #expect(try db.updateMessageTokens(id: "does-not-exist",
            usage: UsageCapture(promptTokens: 1, completionTokens: 1, costUSD: nil, modelID: "m", providerID: "p")) == false)
        #expect(try db.usageDataPoints().isEmpty)
    }

    @Test func updateTokensOverwritesPreviousValue() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "old", providerID: "p"))
        try db.updateMessageTokens(id: "m1",
            usage: UsageCapture(promptTokens: 999, completionTokens: 1, costUSD: nil, modelID: "new", providerID: "p"))
        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.promptTokens == 999)
        #expect(points.first?.model == "new")
    }
}
