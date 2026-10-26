import Testing
import Foundation
@testable import myCoder

/// Round 30 — live user-pipeline finding: `MessageStore.update()` persists via
/// `saveMessage`, which ran a plain INSERT. Every streaming/status update of an
/// already-inserted message (assistant placeholder → statuses → final text)
/// failed with `UNIQUE constraint failed: messages.id`, so the database kept
/// the EMPTY bubble forever while memory had the real text. Persistence must be
/// idempotent per message id: re-saving updates the row.
@Suite("Round 30 — message persistence is an upsert, streaming survives reload", .serialized)
struct Round30MessageUpsertTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-r30-upsert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("re-saving the same message id updates content instead of failing")
    func resaveUpdatesContent() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "r30-s1", projectId: projectPath,
                                            title: "Chat", directory: projectPath)

        let m = Message(id: "r30-m1", role: .assistant, content: "")
        DatabaseBridge.shared.saveMessage(m, sessionId: "r30-s1")

        var updated = m
        updated.content = "final streamed answer"
        updated.isFinished = true
        DatabaseBridge.shared.saveMessage(updated, sessionId: "r30-s1")

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: "r30-s1")
        #expect(loaded.count == 1, "upsert must not create duplicate rows, got \(loaded.count)")
        #expect(loaded.first?.content == "final streamed answer",
                "streamed content must reach the database, got '\(loaded.first?.content ?? "")'")
    }

    @Test("global/legacy database path also upserts on re-save")
    func globalDatabaseUpserts() throws {
        // The temporary-session route uses DatabaseManager (global). It must
        // match ProjectDatabaseManager's replace-on-conflict semantics.
        let db = DatabaseManager.createInMemory()
        try db.insertMessage(id: "r30-m2", sessionId: "r30-temp", role: "assistant", content: "")
        try db.insertMessage(id: "r30-m2", sessionId: "r30-temp", role: "assistant",
                             content: "temp answer")
        let rows = try db.getMessagesBySession(sessionId: "r30-temp")
        #expect(rows.count == 1, "upsert must not create duplicate rows, got \(rows.count)")
        #expect(rows.first?.content == "temp answer",
                "streamed content must reach the database, got '\(rows.first?.content ?? "")'")
    }
}
