import Foundation

/// Canonical myCoder filesystem identity.
/// App dir: `~/.mycoder` + `<project>/.mycoder`.
enum MyCoderPaths {
    static let appDirName = ".mycoder"
    static let bundlePrefix = "com.mycoder"

    static func appDir(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(appDirName, isDirectory: true)
    }

    /// Legacy project registry file. Projects are stored in the global
    /// database now; this path is kept only so the one-time importer can read
    /// an older file and the full-storage reset can clean it up.
    static func registryURL(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("projects.json")
    }

    static func projectDataDir(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath).appendingPathComponent(appDirName, isDirectory: true)
    }

    static func snapshotsDir(projectPath: String) -> URL {
        projectDataDir(projectPath: projectPath).appendingPathComponent("snapshots", isDirectory: true)
    }

    static func todosURL(projectPath: String) -> URL {
        projectDataDir(projectPath: projectPath).appendingPathComponent("todos.json")
    }

    static func backupsDir(projectPath: String) -> URL {
        projectDataDir(projectPath: projectPath).appendingPathComponent("backups", isDirectory: true)
    }

    static func deletedBackupsDir(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("deleted-backups", isDirectory: true)
    }

    static func logsDir(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("logs", isDirectory: true)
    }

    static let globalDatabaseFilename = "mycoder.db"

    static func globalDatabaseURL(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent(globalDatabaseFilename)
    }

    // MARK: - Agent resources (skills / MCP / commands / plugins / sessions)

    static func skillsDir(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("skills", isDirectory: true)
    }

    static func skillDir(id: String, homeDirectory: URL) -> URL {
        skillsDir(homeDirectory: homeDirectory).appendingPathComponent(id, isDirectory: true)
    }

    static func skillFile(id: String, homeDirectory: URL) -> URL {
        skillDir(id: id, homeDirectory: homeDirectory).appendingPathComponent("SKILL.md")
    }

    static func mcpConfigURL(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("mcp.json")
    }

    static let skillsRegistryRelativePath = ".mycoder/skills/registry.json"
    static let mcpRegistryRelativePath = ".mycoder/mcp/registry.json"
    static let lspRegistryRelativePath = ".mycoder/lsp/registry.json"

    /// JSON config of installed/enabled language servers (LSP). Mirrors how
    /// `mcp.json` stores MCP servers: id → {command, args, languages, disabled}.
    static func lspConfigURL(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("lsp.json")
    }

    /// Persisted goals (ЦЕЛЬ) list: `~/.mycoder/goals.json`.
    static func goalsURL(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("goals.json")
    }

    static func commandsDir(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("commands", isDirectory: true)
    }

    static func pluginsDir(homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory).appendingPathComponent("plugins", isDirectory: true)
    }

    static func webSessionsDir(providerId: String, homeDirectory: URL) -> URL {
        appDir(homeDirectory: homeDirectory)
            .appendingPathComponent("web-sessions/\(providerId)", isDirectory: true)
    }

    static func logFile(name: String, homeDirectory: URL) -> URL {
        logsDir(homeDirectory: homeDirectory).appendingPathComponent(name)
    }

    /// True for the canonical app-data directory, so watchers, indexers and
    /// gitignore logic ignore it.
    static func isAppDataPathComponent(_ component: String) -> Bool {
        component == appDirName
    }

    /// Indexer excludes: canonical app-data directory + generated/artifact
    /// directories. `defaultExcludes` must stay conservative (source dirs
    /// are never excluded), but media/voice runtimes and backup folders can
    /// be hundreds of GB and would make any baseline scan unbounded
    /// (observed: personalfairytales with 141 GB `.voice-runtime`).
    static let defaultExcludes: [String] = [
        ".git", "node_modules", ".build", "DerivedData", ".mycoder",
        "dist", "build", ".next", ".venv", "venv", "__pycache__", ".idea", ".swiftpm",
        ".voice-runtime", ".voice-data", ".backups", ".codegraph",
        ".pytest_cache", ".mypy_cache", ".ruff_cache", ".repowise", ".DS_Store"
    ]

    static func bundleKey(_ suffix: String) -> String {
        "\(bundlePrefix).\(suffix)"
    }

}
