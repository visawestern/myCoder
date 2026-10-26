import Foundation

/// A project entry in the lightweight global registry (plan Раздел 8 Блок 2 п.11).
/// The global DB stores ONLY this registry (paths + settings), not full history —
/// so startup is fast and history lives in per-project DBs (Раздел 7).
struct ProjectRegistryEntry: Codable, Identifiable, Equatable {
    /// Stable id = canonical project path (plan Блок 2 п.17).
    let id: String
    var name: String
    var path: String
    var lastOpenedAt: Date
    var defaultProviderID: String?
    var defaultModelID: String?
    var archivedAt: Date?

    var isArchived: Bool { archivedAt != nil }

    init(path: String,
         name: String? = nil,
         lastOpenedAt: Date = Date(),
         defaultProviderID: String? = nil,
         defaultModelID: String? = nil,
         archivedAt: Date? = nil) {
        self.id = IdentifierNormalization.projectID(for: path)
        self.path = IdentifierNormalization.projectID(for: path)
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.lastOpenedAt = lastOpenedAt
        self.defaultProviderID = defaultProviderID
        self.defaultModelID = defaultModelID
        self.archivedAt = archivedAt
    }
}

struct ProjectRegistryDocument: Codable, Equatable {
    var projects: [ProjectRegistryEntry]
}

/// Round 14 (devil's-advocate re-audit): ONE id per project — the canonical
/// absolute path (plan Раздел 8 п.17). `createNewProject` and `addWorkspace`
/// used to mint TWO different UUIDs for the same folder (п.5/п.18). Both must
/// derive the id from the normalized path so the registry, DB rows, sessions
/// and navigation all agree on a single identity.
enum ProjectIdentityLogic {
    /// The single, stable id of a project = canonicalized absolute path.
    /// Symlink-resolving normalization collapses "/tmp/p" and "/private/tmp/p"
    /// (macOS /tmp → /private/tmp), then trailing-slash is stripped, so
    /// "…/proj", "…/proj/" and "…/private/tmp/proj" map to ONE id.
    static func projectID(for path: String) -> String {
        IdentifierNormalization.projectID(for: ChatSession.normalizedPath(path))
    }
}

/// Pure administration of the project registry (plan Раздел 8 Блок 3).
/// The global DB layer persists this; all decisions are testable here.
enum ProjectRegistryLogic {
    static var registryRelativePath: String { "\(MyCoderPaths.appDirName)/projects.json" }

    static func registryURL(homeDirectory: URL) -> URL {
        MyCoderPaths.registryURL(homeDirectory: homeDirectory)
    }

    static func load(homeDirectory: URL, fileManager: FileManager = .default) -> [ProjectRegistryEntry] {
        let url = registryURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProjectRegistryDocument.self, from: data))?.projects ?? []
    }

    static func save(_ projects: [ProjectRegistryEntry], homeDirectory: URL, fileManager: FileManager = .default) throws {
        let url = registryURL(homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ProjectRegistryDocument(projects: projects)).write(to: url, options: .atomic)
    }

    /// Register a project, deduplicating by canonical path (plan Блок 3 п.32:
    /// reopening the same folder must NOT create a duplicate — fixes UUID pileup).
    static func upsert(_ entry: ProjectRegistryEntry, into projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        var result = projects
        if let idx = result.firstIndex(where: { $0.id == entry.id }) {
            // Preserve archive state / settings; refresh lastOpenedAt.
            var existing = result[idx]
            existing.name = entry.name
            existing.lastOpenedAt = entry.lastOpenedAt
            result[idx] = existing
        } else {
            result.append(entry)
        }
        return result
    }

    /// Register a project when it is created or opened (Round 14: the registry
    /// was orphaned — `upsert` had no production caller, so the storage panel
    /// stayed empty in real use; plan Раздел 8 п.11/п.32). Idempotent by
    /// canonical path: registering the same folder twice keeps ONE entry.
    static func registerProject(path: String, name: String?, into projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        upsert(ProjectRegistryEntry(path: path, name: name), into: projects)
    }

    static func archive(id: String, at date: Date, in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.map { var p = $0; if p.id == id { p.archivedAt = date }; return p }
    }

    static func restore(id: String, in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.map { var p = $0; if p.id == id { p.archivedAt = nil }; return p }
    }

    static func remove(id: String, in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.filter { $0.id != id }
    }

    /// Active (non-archived) projects for the Sidebar.
    static func active(_ projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.filter { !$0.isArchived }.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    static func archived(_ projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.filter { $0.isArchived }
    }

    /// "Orphaned" projects whose path no longer exists on disk (plan Блок 3 п.31).
    static func orphaned(_ projects: [ProjectRegistryEntry], fileManager: FileManager = .default) -> [ProjectRegistryEntry] {
        projects.filter { !fileManager.fileExists(atPath: $0.path) }
    }

    /// Re-link an orphaned project to its new location (plan Блок 3 п.31:
    /// "Найти новый путь"). The id is re-derived from the normalized absolute
    /// path; settings (archive status) are preserved; the name is refreshed
    /// from the folder name.
    static func relink(_ entry: ProjectRegistryEntry, toNewPath newPath: String) -> ProjectRegistryEntry {
        ProjectRegistryEntry(
            path: newPath,
            name: nil, // init derives the folder name from the new path
            lastOpenedAt: entry.lastOpenedAt,
            defaultProviderID: entry.defaultProviderID,
            defaultModelID: entry.defaultModelID,
            archivedAt: entry.archivedAt
        )
    }

    /// Relink by id inside a whole registry (returns the updated list).
    static func relink(id: String, toNewPath newPath: String, in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        projects.map { $0.id == id ? relink($0, toNewPath: newPath) : $0 }
    }

    /// Projects not opened in the last N days (for bulk-archive suggestion, plan Блок 3 п.25).
    static func inactiveLongerThan(days: Int, now: Date = Date(), in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return projects.filter { !$0.isArchived && $0.lastOpenedAt < cutoff }
    }

    // MARK: - Dedup on migration (plan Раздел 8 п.47)

    /// Collapse a registry that may contain multiple records for the same
    /// canonical project path (the legacy UUID pileup from Блок 1 п.4 — one
    /// project could end up with several rows under different ids/paths).
    ///
    /// Rule per canonical path:
    /// - ONE record survives, re-keyed to the canonical normalized path;
    /// - the most recently opened record contributes name/provider/model;
    /// - the archive flag survives if ANY duplicate was archived (a user
    ///   decision must not be lost by a duplicate merge).
    static func deduplicated(_ projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        var canonical: [String: ProjectRegistryEntry] = [:]
        for entry in projects {
            let key = IdentifierNormalization.projectID(for: entry.path)
            guard let existing = canonical[key] else {
                canonical[key] = entry
                continue
            }
            canonical[key] = merge(existing, with: entry)
        }
        return canonical.values.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Merge two duplicate records for the same canonical path.
    private static func merge(_ a: ProjectRegistryEntry, with b: ProjectRegistryEntry) -> ProjectRegistryEntry {
        let newest = a.lastOpenedAt >= b.lastOpenedAt ? a : b
        let other = a.lastOpenedAt >= b.lastOpenedAt ? b : a
        return ProjectRegistryEntry(
            path: newest.path,
            name: newest.name,
            lastOpenedAt: newest.lastOpenedAt,
            defaultProviderID: newest.defaultProviderID ?? other.defaultProviderID,
            defaultModelID: newest.defaultModelID ?? other.defaultModelID,
            archivedAt: a.archivedAt ?? b.archivedAt
        )
    }

    /// One-time migration helper: load the registry file, collapse duplicate
    /// canonical paths, and rewrite it in place. Idempotent — a clean registry
    /// is returned unchanged (no churn on re-run). Returns true when a rewrite
    /// actually happened.
    @discardableResult
    static func deduplicateRegistry(homeDirectory: URL, fileManager: FileManager = .default) -> Bool {
        let before = load(homeDirectory: homeDirectory, fileManager: fileManager)
        let after = deduplicated(before)
        guard after != before else { return false }
        try? save(after, homeDirectory: homeDirectory, fileManager: fileManager)
        try? StorageAuditLog.append(action: "registry.deduplicate",
                                    detail: "\(before.count)->\(after.count) entries",
                                    homeDirectory: homeDirectory)
        return true
    }
}
