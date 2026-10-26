import Testing
import Foundation
@testable import myCoder

/// Project backup (plan Раздел 8 п.29/п.30): export the project's .mycoder
/// data directory (project.db + snapshots) to a single .zip archive and
/// restore it back. Pure planning logic is tested here; the zip itself is
/// produced by the platform `ditto` tool (never a stub).
@Suite("Project backup export/import (plan Раздел 8 п.29/п.30)")
struct ProjectBackupTests {

    @Test func planListsOnlyDataInsideProject() {
        let plan = ProjectBackupLogic.plan(projectPath: "/Users/x/Projects/MyApp")
        #expect(plan.sourceDir.path.hasSuffix("/Projects/MyApp/.mycoder"))
        #expect(plan.archiveName == "MyApp-mycoder-backup.zip")
        // User files must never be swept into the archive — only .mycoder.
        #expect(!plan.sourceDir.path.hasSuffix("/MyApp"))
        #expect(plan.sourceDir.path.hasSuffix("/MyApp/.mycoder"))
    }

    @Test func planUsesProjectFolderNameForArchive() {
        let plan = ProjectBackupLogic.plan(projectPath: "/deep/nested/path/Folder Name")
        #expect(plan.archiveName == "Folder Name-mycoder-backup.zip")
    }

    @Test func exportAndImportRoundTrip() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let projectDir = home.appendingPathComponent("Proj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Seed a real per-project DB with content.
        let db = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        try db.insertSession(id: "s1", title: "Backup session", directory: projectDir.path)
        try db.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "hello", isFinished: true)

        // Add a snapshot file inside .mycoder/snapshots/.
        let snapDir = ProjectDatabaseLocator.snapshotsDir(projectPath: projectDir.path)
        try FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
        let snapFile = snapDir.appendingPathComponent("snap-1.json")
        try "{\"change\":\"x\"}".write(to: snapFile, atomically: true, encoding: .utf8)

        // Export.
        let archiveURL = home.appendingPathComponent("backup.zip")
        let exportResult = ProjectBackupLogic.export(projectPath: projectDir.path, to: archiveURL)
        #expect(exportResult == true, "export failed")
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))

        // Now delete the project data and restore from the archive.
        try? FileManager.default.removeItem(at: ProjectDatabaseLocator.projectMimoDir(projectPath: projectDir.path))
        #expect(!FileManager.default.fileExists(atPath: snapFile.path))

        let importResult = ProjectBackupLogic.importBackup(from: archiveURL, projectPath: projectDir.path)
        #expect(importResult == true, "import failed")

        // project.db and snapshots must be back.
        #expect(FileManager.default.fileExists(atPath: snapFile.path))
        let restoredDB = try ProjectDatabaseManager.manager(forProjectPath: projectDir.path)
        let count = try restoredDB.sessionCount()
        #expect(count >= 1)
    }

    @Test func exportMissingProjectReturnsFalse() {
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-backup-\(UUID().uuidString).zip")
        let result = ProjectBackupLogic.export(
            projectPath: "/definitely/missing/\(UUID().uuidString)",
            to: archiveURL
        )
        #expect(result == false)
    }
}
