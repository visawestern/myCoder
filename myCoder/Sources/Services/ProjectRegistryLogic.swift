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
/// The global database (`~/.mycoder/mycoder.db`, `projects` table) is the ONLY
/// persistence layer for projects: opening/creating a project writes a row,
/// and archive state / per-project defaults live in that same row (user
/// directive 2026-10-28). This enum stays free of I/O and is unit-testable.
enum ProjectRegistryLogic {

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

    /// Drop registry records whose folder no longer exists. Used by the
    /// Storage panel's bulk cleanup; project data on disk is untouched.
    static func removingOrphaned(_ projects: [ProjectRegistryEntry], fileManager: FileManager = .default) -> [ProjectRegistryEntry] {
        projects.filter { fileManager.fileExists(atPath: $0.path) }
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
}

/// Database-backed project registry: the one and only persistence layer for
/// projects. There is deliberately no JSON file any more — `~/.mycoder/
/// projects.json` is treated as a legacy import source and archived after the
/// first successful read (see `importLegacyJSON`).
enum ProjectRegistryStore {
    /// All projects, most recently opened first (the database defines the
    /// order). `store` is injectable so tests can use an isolated in-memory
    /// database instead of the process-wide singleton.
    static func load(store: DatabaseManager = .shared) -> [ProjectRegistryEntry] {
        let records = (try? store.getAllProjects()) ?? []
        return records.map(entry(from:))
    }

    /// Replace the whole registry (see `DatabaseManager.replaceProjectRegistry`).
    static func replace(_ entries: [ProjectRegistryEntry], store: DatabaseManager = .shared) throws {
        try store.replaceProjectRegistry(entries.map(record(from:)))
    }

    /// Register a project when it is created or opened (idempotent by
    /// canonical path). `addWorkspace` writes the row through the normal
    /// project upsert; this helper exists for import/backup paths.
    static func register(path: String, name: String? = nil, store: DatabaseManager = .shared) throws {
        let entries = ProjectRegistryLogic.upsert(
            ProjectRegistryEntry(path: path, name: name),
            into: load(store: store)
        )
        try replace(entries, store: store)
    }

    static func archive(id: String, at date: Date, store: DatabaseManager = .shared) throws {
        let entries = ProjectRegistryLogic.archive(id: id, at: date, in: load(store: store))
        try replace(entries, store: store)
    }

    static func restore(id: String, store: DatabaseManager = .shared) throws {
        let entries = ProjectRegistryLogic.restore(id: id, in: load(store: store))
        try replace(entries, store: store)
    }

    static func remove(id: String, store: DatabaseManager = .shared) throws {
        let entries = ProjectRegistryLogic.remove(id: id, in: load(store: store))
        try replace(entries, store: store)
    }

    /// Re-point a project after its folder was moved/renamed. The database
    /// keeps the row's `stable_id` and creation date, so a relink never
    /// breaks history provenance.
    static func relink(id: String, toNewPath newPath: String, store: DatabaseManager = .shared) throws {
        let entries = load(store: store)
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let normalized = ChatSession.normalizedPath(newPath)
        _ = try store.relinkProject(
            oldId: id,
            newPath: normalized,
            name: URL(fileURLWithPath: normalized).lastPathComponent
        )
        var updated = entries.filter { $0.id != id }
        updated.append(ProjectRegistryLogic.relink(entry, toNewPath: normalized))
        try replace(updated, store: store)
    }

    /// One-time import of the legacy `~/.mycoder/projects.json` registry.
    /// The database wins: rows are seeded only when the `projects` table is
    /// empty, so a live install can never be overwritten by a stale file.
    /// The file is archived (renamed) afterwards, never silently deleted.
    @discardableResult
    static func importLegacyJSON(
        homeDirectory: URL,
        store: DatabaseManager = .shared,
        fileManager: FileManager = .default
    ) -> Bool {
        let url = MyCoderPaths.registryURL(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        defer { archiveLegacyFile(url, fileManager: fileManager) }
        guard let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(ProjectRegistryDocument.self, from: data) else {
            return false
        }
        guard load(store: store).isEmpty else { return false }
        let deduplicated = ProjectRegistryLogic.deduplicated(document.projects)
        do {
            try replace(deduplicated, store: store)
            return true
        } catch {
            print("❌ Legacy project registry import failed: \(error)")
            return false
        }
    }

    /// Rename `projects.json` out of the way so the importer never runs twice
    /// and the user's old file remains available for manual recovery.
    private static func archiveLegacyFile(_ url: URL, fileManager: FileManager) {
        let stamp = Int(Date().timeIntervalSince1970)
        let archived = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).legacy-\(stamp)")
        do {
            try fileManager.moveItem(at: url, to: archived)
        } catch {
            print("❌ Could not archive legacy project registry: \(error)")
        }
    }

    private static func entry(from record: ProjectRecord) -> ProjectRegistryEntry {
        ProjectRegistryEntry(
            path: record.path,
            name: record.name,
            lastOpenedAt: record.lastOpenedAt,
            defaultProviderID: record.defaultProviderID,
            defaultModelID: record.defaultModelID,
            archivedAt: record.archivedAt
        )
    }

    private static func record(from entry: ProjectRegistryEntry) -> ProjectRegistryRecord {
        ProjectRegistryRecord(
            id: entry.id,
            name: entry.name,
            path: entry.path,
            lastOpenedAt: entry.lastOpenedAt,
            archivedAt: entry.archivedAt,
            defaultProviderID: entry.defaultProviderID,
            defaultModelID: entry.defaultModelID
        )
    }
}
