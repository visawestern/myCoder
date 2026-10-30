import Testing
import Foundation
@testable import myCoder

/// Chats live ONLY in the program database (user directive 2026-10-29: "они
/// должны у нас быть все в базе данных программы а не храниться в папке с
/// проектом"). The project folder is never read for chats — even if an old
/// per-project database file with chats still exists on disk.
@Suite("Чаты проекта — только база программы (папка не читается)", .serialized)
@MainActor
struct SessionRouteRecoveryTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-route-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("loadSessions не читает чаты из папки проекта, даже если там есть старые БД")
    func projectFolderChatsAreNeverRead() throws {
        let projectPath = try makeTempProjectDir("forbidden")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        // Legacy per-project database with chats: must be ignored completely.
        let sessionID = "legacy-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(id: sessionID, title: "Legacy chat", directory: projectPath)
        try projectDB.insertMessage(id: "\(sessionID)-m1", sessionId: sessionID, role: "user", content: "stored in the project file")

        let sessions = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        #expect(sessions.isEmpty, "project-folder chats must never appear")

        let programSessionIDs = try DatabaseManager.shared.getSessionsByProject(projectId: ChatSession.normalizedPath(projectPath)).map(\.id)
        #expect(programSessionIDs.isEmpty, "nothing may be copied into the program database")
    }

    @Test("повторный load — пусто, никакой миграции из папки")
    func reloadStaysEmpty() throws {
        let projectPath = try makeTempProjectDir("reload")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let sessionID = "legacy-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(id: sessionID, title: "Old", directory: projectPath)

        _ = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        _ = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        #expect(DatabaseBridge.shared.loadSessions(projectId: projectPath).isEmpty)
    }

    @Test("проект без legacy-базы не создаёт папку в проекте")
    func noLegacyStoreCreatesNoProjectFile() throws {
        let projectPath = try makeTempProjectDir("fresh")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        #expect(!ProjectDatabaseManager.hasExistingDatabase(projectPath: projectPath),
                "opening a project must not create a chat database inside the project folder")
    }
}
