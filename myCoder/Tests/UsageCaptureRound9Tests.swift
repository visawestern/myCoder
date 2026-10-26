import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseManager.insertMessage writes usage (round 9)")
struct DatabaseManagerInsertUsageTests {

    private func makeDB() throws -> DatabaseManager {
        let db = DatabaseManager(inMemory: true)
        try db.insertSession(id: "s1", projectId: "p1", title: "t", directory: "/tmp")
        return db
    }

    @Test func insertMessageWithUsageWritesTokenColumns() throws {
        let db = try makeDB()
        let usage = UsageCapture(promptTokens: 200, completionTokens: 80, costUSD: 0.02, modelID: "gpt-4o", providerID: "openai")
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "done", usage: usage)

        let points = try db.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.promptTokens == 200)
        #expect(points.first?.completionTokens == 80)
        #expect(points.first?.model == "gpt-4o")
        #expect(points.first?.provider == "openai")
    }

    @Test func insertMessageWithNilUsageLeavesTokenColumnsNull() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "hi", usage: nil)
        #expect(try db.usageDataPoints().isEmpty)
    }

    @Test func insertMessageDefaultUsageNil() throws {
        let db = try makeDB()
        try db.insertMessage(id: "m1", sessionId: "s1", role: "assistant", content: "hi")
        #expect(try db.usageDataPoints().isEmpty)
    }
}
