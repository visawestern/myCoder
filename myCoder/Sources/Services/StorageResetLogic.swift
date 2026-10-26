import Foundation

/// Pure logic for the explicit storage-reset scenario (plan Раздел 8 Блок 1 п.10).
/// The app is HTTP-only (no local CLI) — there is no CLI history to clear and
/// no auto-import switch, so the single honest scenario is "clear the app
/// database". Decoupled from the UI so it is unit-testable without touching
/// real databases.
enum StorageResetScope: Equatable {
    /// Clear the app database (`~/.mycoder/mimo.db`).
    case appCacheOnly
}

struct StorageResetPlan: Equatable {
    let scope: StorageResetScope
    /// Paths that will be deleted by this scenario.
    let deletesPaths: [String]
}

enum StorageResetLogic {
    /// Build the concrete plan for a given scope. Paths are relative to the
    /// provided home directory.
    static func plan(for scope: StorageResetScope,
                     homeDirectory: URL) -> StorageResetPlan {
        let dbURL = MyCoderPaths.globalDatabaseURL(homeDirectory: homeDirectory)
        switch scope {
        case .appCacheOnly:
            return StorageResetPlan(scope: scope, deletesPaths: [dbURL.path])
        }
    }

    /// Human-readable summary of what a plan will do (shown in the confirm alert).
    static func summary(for plan: StorageResetPlan) -> String {
        var lines: [String] = []
        lines.append("Paths to delete:")
        lines.append(contentsOf: plan.deletesPaths.map { "  - \($0)" })
        return lines.joined(separator: "\n")
    }
}

/// Normalizes project/session identifiers to fix the "pile of UUIDs" root cause
/// (plan Раздел 8 Блок 1 п.4 / Блок 2 п.17). A project id is the canonicalized
/// absolute path; a session id is a stable UUID minted once.
enum IdentifierNormalization {
    /// Canonicalize a project path to a stable id (resolve symlinks, strip trailing slash).
    static func projectID(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let standardized = url.standardizedFileURL.path
        return standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// True if two raw paths refer to the same canonical project.
    static func sameProject(_ a: String, _ b: String) -> Bool {
        projectID(for: a) == projectID(for: b)
    }
}
