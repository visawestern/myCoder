import Foundation

/// Confirmation gate for destructive project deletion (plan Раздел 8 п.24/п.54).
/// GitHub-style "type the project name to delete" so a stray click can never
/// wipe a project's data. The plan also requires the confirm dialog to state
/// explicitly WHAT will be deleted (data dir only — user files are untouched).
enum ProjectDeleteConfirmation {

    /// Whether the typed text equals the project name. Trimmed on input only;
    /// comparison is case-sensitive, exactly like the GitHub repo-delete flow.
    static func isConfirmed(projectName: String, typed: String) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == projectName
    }

    /// Human-readable list of what will be physically deleted for the confirm
    /// dialog (plan п.24: "с указанием, что будет удалено физически").
    static func deletionDescription(projectPath: String) -> String {
        let dataDir = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
        let db = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        let snapshots = ProjectDatabaseLocator.snapshotsDir(projectPath: projectPath)
        return """
        • \(dataDir.path)/
        • \(db.path)
        • \(snapshots.path)/

        Your project files on disk are NOT deleted.
        """
    }
}
