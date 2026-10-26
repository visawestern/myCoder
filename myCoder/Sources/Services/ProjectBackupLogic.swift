import Foundation

/// Project backup plan (plan Раздел 8 п.29/п.30). Export bundles the project's
/// `.mycoder/` data directory (project.db + snapshots) into a single .zip via
/// the platform `ditto` tool; import restores it. User files are never touched.
struct ProjectBackupPlan: Equatable {
    let sourceDir: URL
    let archiveName: String
}

enum ProjectBackupLogic {

    /// Compute what a backup contains and its archive name.
    static func plan(projectPath: String) -> ProjectBackupPlan {
        let sourceDir = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
        let folderName = (projectPath as NSString).lastPathComponent
        return ProjectBackupPlan(sourceDir: sourceDir,
                                 archiveName: "\(folderName)-mycoder-backup.zip")
    }

    /// Export the project's `.mycoder/` directory to a .zip at `destination`.
    /// Uses `/usr/bin/ditto -c -k` (macOS built-in, no third-party deps).
    @discardableResult
    static func export(projectPath: String, to destination: URL) -> Bool {
        let plan = ProjectBackupLogic.plan(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: plan.sourceDir.path) else { return false }
        // ditto keeps the .mycoder folder name inside the archive.
        let parent = plan.sourceDir.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", plan.sourceDir.path, destination.path]
        process.currentDirectoryURL = parent
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
                && FileManager.default.fileExists(atPath: destination.path)
        } catch {
            return false
        }
    }

    /// Restore a previously exported .zip into the project's `.mycoder/`
    /// directory. Never touches files outside that directory.
    @discardableResult
    static func importBackup(from archiveURL: URL, projectPath: String) -> Bool {
        let plan = ProjectBackupLogic.plan(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return false }
        // Drop any pooled connection first: the archive replaces files that an
        // open ProjectDatabaseManager may still hold handles on (SQLite would
        // otherwise read the old inode → disk I/O error).
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        // Recreate the .mycoder dir so ditto can expand into it.
        try? FileManager.default.createDirectory(at: plan.sourceDir,
                                                 withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, plan.sourceDir.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
