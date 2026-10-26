import Foundation

/// Auto-backup of a per-project DB before potentially dangerous operations
/// (plan Раздел 8 п.49): a copy of `project.db` is kept in
/// `<project>/.mycoder/backups/` with retention by count and by age. Backups
/// stay inside the project's own data dir — user files are never touched.
enum ProjectAutoBackupLogic {

    /// The backups directory for a project (created on demand).
    static func backupDirectory(projectPath: String) -> URL {
        ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
            .appendingPathComponent("backups", isDirectory: true)
    }

    /// Copy the project's `project.db` into backups/ with a timestamped name.
    /// Returns the new backup URL, or nil when the DB is missing.
    @discardableResult
    static func createBackup(projectPath: String) throws -> URL? {
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return nil }
        let dir = backupDirectory(projectPath: projectPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "backup-\(ISO8601DateFormatter().string(from: Date())).db"
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: dbURL, to: dest)
        return dest
    }

    /// List existing backups, newest first (used for retention decisions).
    static func listBackups(projectPath: String) throws -> [URL] {
        let dir = backupDirectory(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [])
        return files
            .filter { $0.pathExtension == "db" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
    }

    /// Prune backups: keep only the newest `keepCount`, and drop any older than
    /// `olderThanDays` days. Both criteria are applied independently.
    static func prune(projectPath: String, keepCount: Int = 5, olderThanDays: Int = 30) throws {
        var backups = try listBackups(projectPath: projectPath)
        // Age-based pruning (newest last for efficient dropping).
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        backups = backups.filter {
            let date = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return date > cutoff
        }
        // Count-based pruning: keep newest `keepCount` (list is newest-first).
        if backups.count > keepCount {
            backups.removeLast(backups.count - keepCount)
        }
        // Anything left that no longer satisfies the criteria is deleted.
        let survivors = Set(backups)
        for file in try listBackups(projectPath: projectPath) where !survivors.contains(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Test helper: write a placeholder backup file (also used to simulate
    /// aged backups for retention tests).
    static func writeBackupFile(named name: String, in projectPath: String, content: String) throws {
        let dir = backupDirectory(projectPath: projectPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.data(using: .utf8)?.write(to: dir.appendingPathComponent(name))
    }

    /// Move the newest backup to a global deleted-backups area so it survives
    /// the project's `.mycoder` directory being removed (plan п.49: the backup
    /// must outlive the deletion it was taken for). Returns the preserved URL.
    /// After the copy, the global area is pruned so it cannot grow unbounded
    /// (kept: newest `deletedKeepCount`, anything older than
    /// `deletedOlderThanDays`).
    @discardableResult
    static func preserveForDeletion(projectPath: String,
                                    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                                    deletedKeepCount: Int = 10,
                                    deletedOlderThanDays: Int = 60) throws -> URL? {
        guard let newest = try listBackups(projectPath: projectPath).first else { return nil }
        let deletedDir = deletedBackupsDirectory(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: deletedDir, withIntermediateDirectories: true)
        let folder = (projectPath as NSString).lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = deletedDir.appendingPathComponent("\(folder)-\(stamp).db")
        try FileManager.default.copyItem(at: newest, to: dest)
        try? pruneDeletedBackups(homeDirectory: homeDirectory,
                                 keepCount: deletedKeepCount,
                                 olderThanDays: deletedOlderThanDays)
        return dest
    }

    /// The global deleted-backups directory (created on demand).
    static func deletedBackupsDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        MyCoderPaths.deletedBackupsDir(homeDirectory: homeDirectory)
    }

    /// Preserved backups, newest first (same ordering as `listBackups`).
    static func listDeletedBackups(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [URL] {
        let dir = deletedBackupsDirectory(homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [])
        return files
            .filter { $0.pathExtension == "db" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
    }

    /// Prune the global deleted-backups area: keep only the newest
    /// `keepCount`, and drop anything older than `olderThanDays` days. Both
    /// criteria are applied independently, mirroring `prune`.
    static func pruneDeletedBackups(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                                    keepCount: Int = 10,
                                    olderThanDays: Int = 60) throws {
        var backups = try listDeletedBackups(homeDirectory: homeDirectory)
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        backups = backups.filter {
            let date = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return date > cutoff
        }
        if backups.count > keepCount {
            backups.removeLast(backups.count - keepCount)
        }
        let survivors = Set(backups)
        for file in try listDeletedBackups(homeDirectory: homeDirectory) where !survivors.contains(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Test helper: write a placeholder file into the deleted-backups area.
    static func writeDeletedBackupFile(named name: String,
                                       homeDirectory: URL,
                                       content: String) throws {
        let dir = deletedBackupsDirectory(homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.data(using: .utf8)?.write(to: dir.appendingPathComponent(name))
    }
}
