import Testing
import Foundation
@testable import myCoder

/// E04 (FEATURE_TEST_REPORT): integrityCheck was never invoked on project open
/// — corruption went undetected and there was no restore-from-backup offer
/// (plan Раздел 8 п.48). This suite exercises the new open-time check + the
/// restore-from-backup path against REAL temp project databases.
@Suite("E04 — integrity check on open + restore from backup", .serialized)
struct E04ProjectOpenIntegrityTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-e04-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func writeGarbageOver(_ dbURL: URL) throws {
        try Data("this is not a sqlite database at all, definitely corrupt garbage".utf8)
            .write(to: dbURL, options: .atomic)
    }

    @Test("Healthy project reports ok at open")
    func healthyPasses() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let result = ProjectOpenIntegrity.checkOnOpen(projectPath: projectPath)
        #expect(result == .ok)
    }

    @Test("First open with no database file is not corruption")
    func firstOpenNoDatabaseIsOk() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let result = ProjectOpenIntegrity.checkOnOpen(projectPath: projectPath)
        #expect(result == .ok)
    }

    @Test("Corrupt database is detected at open")
    func corruptDetected() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        try writeGarbageOver(dbURL)

        let result = ProjectOpenIntegrity.checkOnOpen(projectPath: projectPath)
        guard case .corrupt = result else {
            Issue.record("expected .corrupt, got \(result)")
            return
        }
    }

    @Test("Restoring from the latest backup recovers a working database with data intact")
    func restoreRecoversData() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        // Seed a real session + message so we can verify data survives.
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try manager.insertSession(id: "sess-1", title: "E04 seed", directory: projectPath)
        try manager.insertMessage(
            id: "msg-1", sessionId: "sess-1", role: "user",
            content: "original content"
        )
        let seeded = try manager.messageCount()

        // Backup, then corrupt the live database.
        guard let backupURL = try ProjectAutoBackupLogic.createBackup(projectPath: projectPath) else {
            Issue.record("createBackup returned nil")
            return
        }
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        try writeGarbageOver(dbURL)

        let restored = try ProjectOpenIntegrity.restoreLatestBackup(projectPath: projectPath)
        #expect(restored?.standardizedFileURL == backupURL.standardizedFileURL)
        #expect(ProjectOpenIntegrity.checkOnOpen(projectPath: projectPath) == .ok)

        // The data is queryable again through a fresh connection.
        let reopened = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        #expect(try reopened.messageCount() == seeded)
    }

    @Test("Restore without any backup returns nil and does not crash")
    func restoreNoBackup() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        try writeGarbageOver(dbURL)

        let restored = try ProjectOpenIntegrity.restoreLatestBackup(projectPath: projectPath)
        #expect(restored == nil)
    }

    @Test("Restore evicts the pooled connection so the file is read fresh")
    func restoreEvictsPooledConnection() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        _ = try ProjectAutoBackupLogic.createBackup(projectPath: projectPath)
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        try writeGarbageOver(dbURL)

        // With cross-suite interference gone (scoped eviction), the pooled entry
        // from the first open survives, so it stays pooled up to the restore.
        #expect(ProjectDatabaseManager.isPooled(projectPath: projectPath))
        _ = try ProjectOpenIntegrity.restoreLatestBackup(projectPath: projectPath)
        #expect(!ProjectDatabaseManager.isPooled(projectPath: projectPath))
    }

    @Test("Restore removes stale -journal and -wal sidecar files")
    func restoreRemovesSidecars() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        _ = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        _ = try ProjectAutoBackupLogic.createBackup(projectPath: projectPath)
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        try writeGarbageOver(dbURL)
        try Data("stale journal".utf8).write(to: dbURL.appendingPathExtension("journal"))
        try Data("stale wal".utf8).write(to: dbURL.appendingPathExtension("wal"))

        _ = try ProjectOpenIntegrity.restoreLatestBackup(projectPath: projectPath)
        #expect(!FileManager.default.fileExists(atPath: dbURL.appendingPathExtension("journal").path))
        #expect(!FileManager.default.fileExists(atPath: dbURL.appendingPathExtension("wal").path))
    }
}
