import Foundation
import SQLite

/// Per-project memory table. One row per fact, scoped to the project database
/// that already holds sessions and the spec wizard.
struct ProjectMemoryStore {
    let db: Connection

    private static let chunks = Table("memory_chunks")
    private static let id = Expression<String>("id")
    private static let projectId = Expression<String>("project_id")
    private static let kind = Expression<String>("kind")
    private static let text = Expression<String>("text")
    private static let files = Expression<String>("files_json")
    private static let tags = Expression<String>("tags_json")
    private static let sourceMessageId = Expression<String?>("source_message_id")
    private static let createdAt = Expression<Int64>("created_at")
    private static let updatedAt = Expression<Int64>("updated_at")

    /// Idempotent: called every time a project database is opened for memory,
    /// so old databases gain the table without a migration step.
    static func createSchema(_ db: Connection) throws {
        try db.run(chunks.create(ifNotExists: true) { table in
            table.column(id, primaryKey: true)
            table.column(projectId)
            table.column(kind)
            table.column(text)
            table.column(files)
            table.column(tags)
            table.column(sourceMessageId)
            table.column(createdAt)
            table.column(updatedAt)
        })
        try db.run(chunks.createIndex(updatedAt, ifNotExists: true))
    }

    /// Insert or update by id. The creation time of an existing entry is kept,
    /// so re-remembering a fact does not rewrite its history.
    func upsert(_ chunk: ProjectMemoryChunk) throws {
        let existingCreated = try db.pluck(Self.chunks.filter(Self.id == chunk.id))?[Self.createdAt]
        try db.run(Self.chunks.insert(or: .replace,
                                      Self.id <- chunk.id,
                                      Self.projectId <- chunk.projectID,
                                      Self.kind <- chunk.kind,
                                      Self.text <- chunk.text,
                                      Self.files <- Self.encode(chunk.files),
                                      Self.tags <- Self.encode(chunk.tags),
                                      Self.sourceMessageId <- chunk.sourceMessageID,
                                      Self.createdAt <- existingCreated ?? chunk.createdAt,
                                      Self.updatedAt <- chunk.updatedAt))
    }

    func all(limit: Int = 500) throws -> [ProjectMemoryChunk] {
        guard limit > 0 else { return [] }
        let rows = try db.prepare(
            Self.chunks.order(Self.updatedAt.desc, Self.id.asc).limit(limit)
        )
        return rows.compactMap { row in
            ProjectMemoryChunk(
                id: row[Self.id],
                projectID: row[Self.projectId],
                kind: row[Self.kind],
                text: row[Self.text],
                files: Self.decode(row[Self.files]),
                tags: Self.decode(row[Self.tags]),
                sourceMessageID: row[Self.sourceMessageId],
                createdAt: row[Self.createdAt],
                updatedAt: row[Self.updatedAt]
            )
        }
    }

    /// Retrieval by entity, tag or text. The ranking is deterministic (see
    /// `ProjectMemoryRanker`), so a repeated message reuses the same facts.
    func search(_ query: String, limit: Int = 5) throws -> [ProjectMemoryChunk] {
        ProjectMemoryRanker.rank(try all(limit: 500), query: query, limit: limit)
    }

    @discardableResult
    func delete(id chunkID: String) throws -> Bool {
        try db.run(Self.chunks.filter(Self.id == chunkID).delete()) > 0
    }

    func count() throws -> Int {
        try db.scalar(Self.chunks.count)
    }

    // MARK: - Loading for a send

    /// Reads the project's memory for the outgoing turn. Throws when the
    /// project database cannot be opened — the caller turns that into a
    /// visible warning instead of silently sending without memory.
    static func loadChunks(projectPath: String, limit: Int = 500) throws -> [ProjectMemoryChunk] {
        guard !projectPath.isEmpty else { return [] }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        return try manager.makeMemoryStore().all(limit: limit)
    }

    // MARK: - JSON

    private static func encode(_ values: [String]) -> String {
        guard !values.isEmpty,
              let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }
}
