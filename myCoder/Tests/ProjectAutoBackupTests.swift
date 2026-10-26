import Testing
import Foundation
@testable import myCoder

/// Auto-backup of a per-project DB before destructive operations
/// (plan Раздел 8 п.49): backup into `<project>/.mycoder/backups/` with
/// retention by count and by age.
@Suite("Project auto-backup before destructive ops (plan Раздел 8 п.49)")
struct ProjectAutoBackupTests {

    @Test func backupIsCreatedInProjectDir() throws {
        let projectDir = try makeProject()
        defer { try? FileManager.default.removeItem(at: projectDir.deletingLastPathComponent()) }

        // A DB must exist before a backup can be taken.
        let db = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        try db.insertSession(id: "s1", title: "T", directory: projectDir.path)

        let created = try ProjectAutoBackupLogic.createBackup(projectPath: projectDir.path)
        #expect(created != nil)
        let backups = try ProjectAutoBackupLogic.listBackups(projectPath: projectDir.path)
        #expect(backups.count == 1)
        // Backup must live inside the project's own .mycoder/backups, never elsewhere.
        #expect(created!.path.hasPrefix(projectDir.path + "/.mycoder/backups/"))
    }

    @Test func backupAfterMutatingDbHasData() throws {
        let projectDir = try makeProject()
        defer { try? FileManager.default.removeItem(at: projectDir.deletingLastPathComponent()) }

        let db = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        try db.insertSession(id: "s1", title: "T", directory: projectDir.path)
        try db.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "x", isFinished: true)

        guard let url = try ProjectAutoBackupLogic.createBackup(projectPath: projectDir.path) else {
            Issue.record("backup was not created")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        #expect(size > 0)
    }

    @Test func retentionKeepsNewestOnly() throws {
        let projectDir = try makeProject()
        defer { try? FileManager.default.removeItem(at: projectDir.deletingLastPathComponent()) }

        // Simulate 3 prior backups with increasing timestamps.
        try ProjectAutoBackupLogic.writeBackupFile(named: "backup-1.db", in: projectDir.path, content: "a")
        try ProjectAutoBackupLogic.writeBackupFile(named: "backup-2.db", in: projectDir.path, content: "b")
        try ProjectAutoBackupLogic.writeBackupFile(named: "backup-3.db", in: projectDir.path, content: "c")

        try ProjectAutoBackupLogic.prune(projectPath: projectDir.path, keepCount: 2)
        let remaining = try ProjectAutoBackupLogic.listBackups(projectPath: projectDir.path)
        #expect(remaining.count == 2)
        // The two newest (2,3) survive; 1 is pruned.
        let names = Set(remaining.map { $0.lastPathComponent })
        #expect(!names.contains("backup-1.db"))
        #expect(names.contains("backup-2.db"))
        #expect(names.contains("backup-3.db"))
    }

    @Test func pruneOlderThanDays() throws {
        let projectDir = try makeProject()
        defer { try? FileManager.default.removeItem(at: projectDir.deletingLastPathComponent()) }

        try ProjectAutoBackupLogic.writeBackupFile(named: "old.db", in: projectDir.path, content: "x")
        try ProjectAutoBackupLogic.writeBackupFile(named: "fresh.db", in: projectDir.path, content: "y")
        // Age the "old" backup by rewriting its mtime 10 days back.
        let oldURL = ProjectAutoBackupLogic.backupDirectory(projectPath: projectDir.path)
            .appendingPathComponent("old.db")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-10 * 86400)],
            ofItemAtPath: oldURL.path
        )

        try ProjectAutoBackupLogic.prune(projectPath: projectDir.path, olderThanDays: 7)
        let remaining = try ProjectAutoBackupLogic.listBackups(projectPath: projectDir.path)
        #expect(remaining.count == 1)
        #expect(remaining.first?.lastPathComponent == "fresh.db")
    }

    @Test func preserveForDeletionSurvivesProjectRemoval() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pauto-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let projectDir = try makeProject()

        let db = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        try db.insertSession(id: "s1", title: "T", directory: projectDir.path)
        try db.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "x", isFinished: true)
        try ProjectAutoBackupLogic.createBackup(projectPath: projectDir.path)

        // Inject a temp home so the preserved copy never touches the real
        // ~/.mycoder (it used to, which is how real deleted-backups filled up).
        let preserved = try ProjectAutoBackupLogic.preserveForDeletion(
            projectPath: projectDir.path, homeDirectory: home)
        #expect(preserved != nil)
        #expect(!preserved!.path.hasPrefix(projectDir.path))
        #expect(preserved!.path.hasPrefix(home.appendingPathComponent(".mycoder/deleted-backups").path))

        // Now delete the project data entirely — the preserved backup remains.
        try? FileManager.default.removeItem(at: ProjectDatabaseLocator.projectMimoDir(projectPath: projectDir.path))
        #expect(FileManager.default.fileExists(atPath: preserved!.path))
    }

    @Test func deletedBackupsArePrunedByCount() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pauto-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        for i in 1...5 {
            try ProjectAutoBackupLogic.writeDeletedBackupFile(
                named: "Proj-2026-08-0\(i).db", homeDirectory: home, content: "\(i)")
        }
        try ProjectAutoBackupLogic.pruneDeletedBackups(homeDirectory: home, keepCount: 2)
        let remaining = try ProjectAutoBackupLogic.listDeletedBackups(homeDirectory: home)
        #expect(remaining.count == 2)
        // Newest-first ordering: the two newest survive.
        let names = Set(remaining.map { $0.lastPathComponent })
        #expect(!names.contains("Proj-2026-08-01.db"))
        #expect(!names.contains("Proj-2026-08-02.db"))
        #expect(names.contains("Proj-2026-08-04.db"))
        #expect(names.contains("Proj-2026-08-05.db"))
    }

    @Test func deletedBackupsArePrunedByAge() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pauto-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let stale = ProjectAutoBackupLogic.deletedBackupsDirectory(homeDirectory: home)
            .appendingPathComponent("old.db")
        try ProjectAutoBackupLogic.writeDeletedBackupFile(
            named: "old.db", homeDirectory: home, content: "x")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-30 * 86400)],
            ofItemAtPath: stale.path
        )
        try ProjectAutoBackupLogic.writeDeletedBackupFile(
            named: "fresh.db", homeDirectory: home, content: "y")

        try ProjectAutoBackupLogic.pruneDeletedBackups(homeDirectory: home, olderThanDays: 7)
        let remaining = try ProjectAutoBackupLogic.listDeletedBackups(homeDirectory: home)
        #expect(remaining.count == 1)
        #expect(remaining.first?.lastPathComponent == "fresh.db")
    }

    @Test func preserveForDeletionPrunesTheGlobalArea() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pauto-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let projectDir = try makeProject()

        // Pre-fill the global area past the retention cap.
        for i in 1...12 {
            try ProjectAutoBackupLogic.writeDeletedBackupFile(
                named: "Proj-2026-07-0\(i).db", homeDirectory: home, content: "\(i)")
        }
        let db = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        try db.insertSession(id: "s1", title: "T", directory: projectDir.path)
        try ProjectAutoBackupLogic.createBackup(projectPath: projectDir.path)

        try ProjectAutoBackupLogic.preserveForDeletion(
            projectPath: projectDir.path,
            homeDirectory: home,
            deletedKeepCount: 10,
            deletedOlderThanDays: 60)

        let remaining = try ProjectAutoBackupLogic.listDeletedBackups(homeDirectory: home)
        // 12 prefilled + 1 new = 13; count-pruned back to the newest 10.
        #expect(remaining.count == 10)
    }

    // MARK: - Helpers

    private func makeProject() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pauto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let projectDir = home.appendingPathComponent("Proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        // Ensure .mycoder exists so the manager can open a file-backed DB.
        try FileManager.default.createDirectory(
            at: ProjectDatabaseLocator.projectMimoDir(projectPath: projectDir.path),
            withIntermediateDirectories: true
        )
        return projectDir
    }
}
