import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseBridge — sidebar session actions", .serialized)
struct DatabaseBridgeSessionActionsTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-bridge-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("Rename/delete route to the owning project store and report real changes")
    func renameAndDeleteProjectSession() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
            try? FileManager.default.removeItem(atPath: projectPath)
        }

        let bridge = DatabaseBridge()
        bridge.createSession(id: "s1", projectId: projectPath, title: "Old", directory: projectPath)

        #expect(bridge.renameSession(id: "s1", title: "New"))
        let store = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        #expect(try store.getAllSessions().first?.title == "New")

        #expect(bridge.renameSession(id: "missing", title: "X") == false)
        #expect(bridge.deleteSession(id: "s1"))
        #expect(try store.getAllSessions(includeArchived: true).isEmpty)
        #expect(bridge.deleteSession(id: "s1") == false)
    }

    @Test("Opening a chat does not bump its updated_at (no sidebar reshuffle)")
    func unarchivingActiveSessionKeepsTimestamp() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
            try? FileManager.default.removeItem(atPath: projectPath)
        }

        let bridge = DatabaseBridge()
        bridge.createSession(id: "s1", projectId: projectPath, title: "Chat", directory: projectPath)
        let store = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let before = try #require(store.getAllSessions().first { $0.id == "s1" }).updatedAt

        // Selecting a session unarchives it. For an already active session
        // that must be a no-op — otherwise every click reordered the
        // sidebar by moving the chat to the top.
        try store.unarchiveSession(id: "s1")
        let after = try #require(store.getAllSessions().first { $0.id == "s1" }).updatedAt
        #expect(after == before)

        // A real archive/unarchive cycle still updates the timestamp.
        try store.archiveSession(id: "s1")
        try store.unarchiveSession(id: "s1")
        let restored = try #require(store.getAllSessions().first { $0.id == "s1" })
        #expect(restored.isArchived == false)
        #expect(restored.updatedAt >= before)
    }

    @Test("Unarchiving an unknown chat is a no-op, not a crash")
    func unarchivingUnknownSessionDoesNotCrash() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
            try? FileManager.default.removeItem(atPath: projectPath)
        }

        let store = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        // A chat id that is not in this project DB (e.g. a project-less chat
        // opened from the sidebar) must not bring the app down.
        try store.unarchiveSession(id: "does-not-exist")
        #expect(try store.getAllSessions().isEmpty)
    }
}
