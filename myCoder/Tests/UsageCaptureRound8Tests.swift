import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseBridge.saveMessage usage passthrough (round 8)", .serialized)
struct DatabaseBridgeUsagePassthroughTests {
    // Reset shared singleton state before each test to avoid cross-test bleed
    // through DatabaseBridge.shared / the ProjectDatabaseManager pool.
    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-bridge-usage-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func saveMessageWithUsageWritesTokensToProjectDatabase() throws {
        let projectPath = try makeTempProjectDir("usage-round8-with")
        defer {
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s8with", projectId: projectPath, title: "Chat", directory: projectPath)

        let usage = UsageCapture(promptTokens: 300, completionTokens: 120, costUSD: 0.05, modelID: "gpt-4o", providerID: "openai")
        var msg = Message(id: "m8with", role: .assistant, content: "done")
        msg.usage = usage
        DatabaseBridge.shared.saveMessage(msg, sessionId: "s8with")

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let points = try projectDB.usageDataPoints()
        #expect(points.count == 1)
        #expect(points.first?.promptTokens == 300)
        #expect(points.first?.completionTokens == 120)
        #expect(points.first?.model == "gpt-4o")
        #expect(points.first?.provider == "openai")
    }

    @Test func saveMessageWithoutUsageWritesNoTokens() throws {
        let projectPath = try makeTempProjectDir("usage-round8-without")
        defer {
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s8without", projectId: projectPath, title: "Chat", directory: projectPath)

        let msg = Message(id: "m8without", role: .assistant, content: "hi")
        DatabaseBridge.shared.saveMessage(msg, sessionId: "s8without")

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        #expect(try projectDB.usageDataPoints().isEmpty)
    }
}
