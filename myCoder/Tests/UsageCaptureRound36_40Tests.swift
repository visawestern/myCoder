import Testing
import Foundation
@testable import myCoder

@Suite("NULL compatibility + provider aggregation + ProjectDB parity (rounds 36-40)")
struct UsageParityAndNullTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "s1", projectId: "p1", title: "t", directory: "/tmp")
        return db
    }

    // 36: rows with NULL token columns read as 0 (no crash)
    @Test func nullTokenColumnsReadAsZero() throws {
        let db = try makeDB()
        // Insert without usage -> NULL prompt/completion tokens
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "x")
        #expect(try db.usageDataPoints().isEmpty)
    }

    // 37: aggregateByProvider groups correctly
    @Test func aggregateByProviderGroups() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "gpt", providerID: "openai"))
        try db.insertMessage(id: "b", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 200, completionTokens: 100, costUSD: 0.02, modelID: "gpt-4.1", providerID: "openai"))
        try db.insertMessage(id: "c", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 500, completionTokens: 200, costUSD: 0.05, modelID: "claude", providerID: "anthropic"))

        let aggs = UsageStatisticsAggregator.aggregateByProvider(try db.usageDataPoints())
        #expect(aggs.count == 2)
        let openai = aggs.first { $0.key == "openai" }
        #expect(openai?.messageCount == 2)
        #expect(openai?.totalTokens == 450)
    }

    // 38: favoriteModelByUsage (by actual usage, not selection)
    @Test func favoriteModelByUsage() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 10, costUSD: nil, modelID: "small", providerID: "p"))
        try db.insertMessage(id: "b", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 5000, completionTokens: 5000, costUSD: nil, modelID: "big", providerID: "p"))
        #expect(UsageStatisticsAggregator.favoriteModel(try db.usageDataPoints()) == "big")
    }

    // 39: activeDays counts unique calendar days
    @Test func activeDaysUnique() throws {
        let db = try makeDB()
        try db.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p"))
        let points = try db.usageDataPoints()
        #expect(UsageStatisticsAggregator.activeDays(points) == 1)
    }

    // 40: ProjectDB parity - same usage data points as global DB
    @Test func projectDBUsageDataPointsParity() throws {
        let globalDB = try makeDB()
        try globalDB.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "gpt-4o", providerID: "openai"))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir.path); ProjectDatabaseManager.evictProject(projectPath: dir.path) }
        ProjectDatabaseManager.evictProject(projectPath: dir.path)

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: dir.path)
        try projectDB.insertSession(id: "s1", title: "t", directory: dir.path)
        try projectDB.insertMessage(id: "a", sessionId: "s1", role: "assistant", content: "x",
            usage: UsageCapture(promptTokens: 100, completionTokens: 50, costUSD: 0.01, modelID: "gpt-4o", providerID: "openai"))

        let globalPoints = try globalDB.usageDataPoints()
        let projectPoints = try projectDB.usageDataPoints()
        #expect(projectPoints.count == globalPoints.count)
        #expect(projectPoints.first?.promptTokens == 100)
        #expect(projectPoints.first?.completionTokens == 50)
        #expect(projectPoints.first?.costUSD == 0.01)
        #expect(projectPoints.first?.model == "gpt-4o")
    }
}
