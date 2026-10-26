import Foundation

/// Pure logic for the explicit storage-reset scenarios (plan Раздел 8 Блок 1 п.10).
/// The app is HTTP-only (no local CLI): the cache-only scope clears the global
/// app database, while the full scope also removes the project registry and
/// every known per-project database. Decoupled from the UI so it is
/// unit-testable without touching real databases.
enum StorageResetScope: Equatable {
    /// Clear the app database (`~/.mycoder/mimo.db`).
    case appCacheOnly
    /// Wipe the app database, the project registry and every known
    /// per-project database (`<project>/.mycoder/project.db`) plus the
    /// fallback project database directory.
    case fullDatabase
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
                     homeDirectory: URL,
                     projectPaths: [String] = []) -> StorageResetPlan {
        let dbURL = MyCoderPaths.globalDatabaseURL(homeDirectory: homeDirectory)
        switch scope {
        case .appCacheOnly:
            return StorageResetPlan(scope: scope, deletesPaths: [dbURL.path])
        case .fullDatabase:
            var paths = [
                dbURL.path,
                MyCoderPaths.registryURL(homeDirectory: homeDirectory).path
            ]
            for projectPath in projectPaths {
                paths.append(
                    MyCoderPaths.projectDataDir(projectPath: projectPath)
                        .appendingPathComponent("project.db").path
                )
            }
            paths.append(
                MyCoderPaths.appDir(homeDirectory: homeDirectory)
                    .appendingPathComponent("projects", isDirectory: true).path
            )
            var seen = Set<String>()
            let unique = paths.filter { seen.insert($0).inserted }
            return StorageResetPlan(scope: scope, deletesPaths: unique)
        }
    }

    /// Human-readable list of paths a plan will delete. The caller supplies
    /// the localized heading so this stays free of hardcoded UI strings.
    static func summary(for plan: StorageResetPlan) -> String {
        plan.deletesPaths.map { "  - \($0)" }.joined(separator: "\n")
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
