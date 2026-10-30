import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseBridge.saveMessage usage passthrough (round 8)", .serialized)
struct DatabaseBridgeUsagePassthroughTests {
    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-bridge-usage-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func saveMessageWithUsageWritesTokensToProgramDatabase() throws {
        let projectPath = try makeTempProjectDir("usage-round8-with")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s8with-\(UUID().uuidString)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)

        let usage = UsageCapture(promptTokens: 300, completionTokens: 120, costUSD: 0.05, modelID: "gpt-4o", providerID: "openai")
        var msg = Message(id: "m8with-\(UUID().uuidString)", role: .assistant, content: "done")
        msg.usage = usage
        DatabaseBridge.shared.saveMessage(msg, sessionId: sessionID)

        let records = try DatabaseManager.shared.getMessagesBySession(sessionId: sessionID)
        #expect(records.first?.promptTokens == 300)
        #expect(records.first?.completionTokens == 120)
        #expect(records.first?.modelId == "gpt-4o")
        #expect(records.first?.providerId == "openai")
    }

    @Test func saveMessageWithoutUsageWritesNoTokens() throws {
        let projectPath = try makeTempProjectDir("usage-round8-without")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s8without-\(UUID().uuidString)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        let msg = Message(id: "m8without-\(UUID().uuidString)", role: .assistant, content: "hi")
        DatabaseBridge.shared.saveMessage(msg, sessionId: sessionID)

        let records = try DatabaseManager.shared.getMessagesBySession(sessionId: sessionID)
        #expect(records.first?.promptTokens == nil)
        #expect(records.first?.completionTokens == nil)
    }
}
