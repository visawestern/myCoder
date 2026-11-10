import Foundation
import SQLite

extension ProjectDatabaseManager {
    // MARK: - Stable Project Identity (survives folder rename/move)

    /// A UUID minted once, the first time this project's database is
    /// created, and never changed afterwards. Stored inside the project's
    /// own database file (not just in the global registry) so that if the
    /// project folder is later moved or renamed, the orphaned `.mycoder`
    /// directory can still be matched back to its registry entry by this id
    /// rather than by path alone.
    func ensureStableProjectId() throws {
        if try db.pluck(projectMetadata.filter(projectMetadataKey == "stable_id")) != nil {
            return
        }
        try db.run(projectMetadata.insert(
            projectMetadataKey <- "stable_id",
            projectMetadataValue <- UUID().uuidString
        ))
    }

    func stableProjectId() throws -> String {
        guard let row = try db.pluck(projectMetadata.filter(projectMetadataKey == "stable_id")) else {
            throw ProjectDatabaseError.notInitialized
        }
        return row[projectMetadataValue]
    }

    /// Read/write the project-scoped key-value store. Used by the spec wizard
    /// so its draft survives app restarts without a separate global store.
    func metadataValue(forKey key: String) throws -> String? {
        touch()
        guard let row = try db.pluck(projectMetadata.filter(projectMetadataKey == key)) else {
            return nil
        }
        return row[projectMetadataValue]
    }

    func setMetadataValue(_ value: String, forKey key: String) throws {
        touch()
        try db.run(projectMetadata.insert(or: .replace,
                                          projectMetadataKey <- key,
                                          projectMetadataValue <- value))
    }

    /// Spec wizard storage shares this project's connection but owns its own
    /// table boundary. Keeping `db` private means callers cannot bypass the
    /// append-only rules implemented by the store.
    func makeSpecStore() -> ProjectSpecStore {
        touch()
        return ProjectSpecStore(db: db)
    }

    /// Project memory lives in the same database as sessions and the spec
    /// wizard. The table is created on first use, so an existing project
    /// database gains it without a migration step.
    func makeMemoryStore() throws -> ProjectMemoryStore {
        touch()
        try ProjectMemoryStore.createSchema(db)
        return ProjectMemoryStore(db: db)
    }

    /// The task ledger is one row per session in the same project database.
    func makeLedgerStore() throws -> TaskLedgerStore {
        touch()
        try TaskLedgerStore.createSchema(db)
        return TaskLedgerStore(db: db)
    }
}
