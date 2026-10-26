import Foundation

/// Locates the per-project database + snapshot dir (plan Раздел 7 Блок 1 п.4/п.8).
/// Each project gets its own `<project>/.mycoder/project.db` so the global DB
/// stays a small registry (Раздел 8), not a giant history store.
enum ProjectDatabaseLocator {
    static func projectMimoDir(projectPath: String) -> URL {
        MyCoderPaths.projectDataDir(projectPath: projectPath)
    }

    static func databaseURL(projectPath: String) -> URL {
        projectMimoDir(projectPath: projectPath).appendingPathComponent("project.db")
    }

    static func snapshotsDir(projectPath: String) -> URL {
        projectMimoDir(projectPath: projectPath).appendingPathComponent("snapshots", isDirectory: true)
    }

    /// A stable, path-independent project id so a moved/renamed folder can be
    /// re-linked (plan Раздел 7 Блок 2 п.17 / Раздел 8 Блок 2 п.17). Uses the
    /// canonical path as the id source (matches IdentifierNormalization).
    static func stableProjectID(projectPath: String) -> String {
        IdentifierNormalization.projectID(for: projectPath)
    }
}

/// Pure indexing decisions — what to index, what changed — independent of
/// FSEvents/SQLite which live in the app layer (plan Раздел 7 Блок 3).
enum ProjectFileIndexLogic {
    /// Directories/patterns always excluded (plan Блок 3 п.23).
    static let defaultExcludes: [String] = MyCoderPaths.defaultExcludes

    /// Max file size to index by default (plan Блок 3 п.30), bytes.
    static let defaultMaxFileSize = 5 * 1024 * 1024

    /// Maximum UTF-8 text retained per file for search, keeping snapshots bounded.
    static let defaultSearchableTextMaxBytes = 512 * 1024

    /// Whether a relative path should be excluded given exclude dir names and
    /// user gitignore-style patterns.
    static func shouldExclude(relativePath: String,
                             excludes: [String] = defaultExcludes,
                             gitignorePatterns: [String] = []) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        // Exclude if any path component is an excluded directory name.
        if components.contains(where: { excludes.contains($0) }) { return true }
        // Simple gitignore matching: exact segment, or trailing-glob "dir/", or "*.ext".
        for pattern in gitignorePatterns {
            if matchesGitignore(relativePath: relativePath, pattern: pattern) { return true }
        }
        return false
    }

    static func matchesGitignore(relativePath: String, pattern: String) -> Bool {
        var p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !p.hasPrefix("#") else { return false }
        let isDirPattern = p.hasSuffix("/")
        if isDirPattern { p.removeLast() }
        let components = relativePath.split(separator: "/").map(String.init)
        if p.hasPrefix("*.") {
            let ext = String(p.dropFirst(1))   // ".ext"
            return relativePath.hasSuffix(ext)
        }
        // Match a path segment exactly (dir or file name).
        if isDirPattern {
            return components.contains(p)
        }
        return components.contains(p) || relativePath == p
    }

    /// Should a file be indexed given size limit and exclusion (plan Блок 3 п.30).
    static func shouldIndex(relativePath: String,
                           size: Int,
                           excludes: [String] = defaultExcludes,
                           gitignorePatterns: [String] = [],
                           maxFileSize: Int = defaultMaxFileSize) -> Bool {
        if size < 0 || size > maxFileSize { return false }
        if shouldExclude(relativePath: relativePath, excludes: excludes, gitignorePatterns: gitignorePatterns) {
            return false
        }
        return true
    }

    /// Compute the incremental delta between the current index and freshly
    /// scanned files (plan Блок 3 п.26/п.27). Returns files to (re)index and to remove.
    struct IndexDelta: Equatable {
        var toUpsert: [FileIndexRecord]
        var toRemove: [String]     // relative paths no longer present
    }

    /// Collapse malformed duplicate-path snapshots deterministically. The
    /// scanner normally emits unique paths, but persisted JSON can be edited or
    /// corrupted; the last record wins instead of trapping in Dictionary init.
    static func recordsByPath(_ records: [FileIndexRecord]) -> [String: FileIndexRecord] {
        var result: [String: FileIndexRecord] = [:]
        for record in records {
            result[record.path] = record
        }
        return result
    }

    static func computeDelta(current: [FileIndexRecord], scanned: [FileIndexRecord]) -> IndexDelta {
        let currentByPath = recordsByPath(current)
        let scannedByPath = recordsByPath(scanned)

        var toUpsert: [FileIndexRecord] = []
        for path in scannedByPath.keys.sorted() {
            guard let file = scannedByPath[path] else { continue }
            if let existing = currentByPath[path] {
                // Re-index only if hash or mtime changed (plan Блок 3 п.26).
                if existing.hash != file.hash || existing.lastModified != file.lastModified {
                    toUpsert.append(file)
                }
            } else {
                toUpsert.append(file)
            }
        }
        // Removed = in current but not in scan (plan Блок 3 п.27).
        let toRemove = currentByPath.keys.filter { scannedByPath[$0] == nil }.sorted()
        return IndexDelta(toUpsert: toUpsert, toRemove: toRemove)
    }

    /// Infer a language tag from a file extension (for the index/UI).
    static func language(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "json": return "json"
        case "md", "markdown": return "markdown"
        case "yml", "yaml": return "yaml"
        case "sh", "bash": return "shell"
        case "c", "h": return "c"
        case "cpp", "cc", "hpp": return "cpp"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "rb": return "ruby"
        default: return ext.isEmpty ? "text" : ext.lowercased()
        }
    }
}

/// Human-readable indexing status for the UI (plan Блок 3 п.28).
enum ProjectIndexStatus: Equatable {
    case idle
    case indexing(done: Int, total: Int)
    case upToDate(fileCount: Int)
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .indexing(let done, let total): return "Indexing: \(done)/\(total) files"
        case .upToDate(let count): return "Up to date (\(count) files)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
