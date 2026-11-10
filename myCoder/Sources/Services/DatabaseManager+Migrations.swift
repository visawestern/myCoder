import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Schema Migrations
    
    func runMigrationsIfNeeded() throws {
        guard let db = db else { return }
        
        // Create schema version table
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                migrated_at INTEGER NOT NULL
            );
        """)
        
        let currentVersion = try db.scalar("SELECT COALESCE(MAX(version), 0) FROM schema_version") as? Int ?? 0
        
        guard currentVersion < Self.schemaVersion else { return }
        
        // Run migrations sequentially
        for version in (currentVersion + 1)...Self.schemaVersion {
            try runMigration(version)
            try db.run("INSERT OR IGNORE INTO schema_version (version, migrated_at) VALUES (?, ?)",
                      version, Int64(Date().timeIntervalSince1970))
            print("✅ Database migrated to schema version \(version)")
        }
    }
    
    func runMigration(_ version: Int) throws {
        guard let db = db else { return }
        switch version {
        case 1:
            // Initial schema — all tables created in createTables()
            break
        case 2:
            // Registry evolution for the per-project storage + reset-bug
            // fix: `stable_id` survives a project being re-linked at a new
            // path, `auto_import_from_cli` replaces the old "reimport if
            // in-memory sessions look empty" heuristic with an explicit,
            // per-project, default-off opt-in.
            try addColumnIfMissing(table: "projects", column: "stable_id", definition: "TEXT")
            try addColumnIfMissing(table: "projects", column: "auto_import_from_cli", definition: "INTEGER NOT NULL DEFAULT 0")
            // Session goal set via /goal, shown in the TopBar (plan Раздел 5 Блок 1 п.10).
            try addColumnIfMissing(table: "sessions", column: "session_goal", definition: "TEXT")
        case 3:
            // Draft text persistence for sessions (Feature 5: projects don't
            // disappear without messages; store drafts + sent messages).
            try addColumnIfMissing(table: "sessions", column: "draft_text", definition: "TEXT")
        case 4:
            // Durable session -> project routing so a session opened outside
            // the project's own sidebar still resolves its per-project store.
            try db.run(sessionRoutes.create(ifNotExists: true) { t in
                t.column(sessionRouteSessionId, primaryKey: true)
                t.column(sessionRouteProjectPath)
                t.column(sessionRouteUpdatedAt)
            })
        case 5:
            // Sub-agent chats: parent link (column exists since v1) and the
            // lifecycle status shown in the right panel.
            try addColumnIfMissing(table: "sessions", column: "subagent_status", definition: "TEXT")
        case 6:
            // Projects are the single source of truth (user directive
            // 2026-10-28): the archived flag and the per-project default
            // provider/model moved out of `~/.mycoder/projects.json` into the
            // `projects` table so Storage/Sidebar/backup read one database.
            try addColumnIfMissing(table: "projects", column: "archived_at", definition: "INTEGER")
            try addColumnIfMissing(table: "projects", column: "default_provider_id", definition: "TEXT")
            try addColumnIfMissing(table: "projects", column: "default_model_id", definition: "TEXT")
        default:
            break
        }
    }

    func addColumnIfMissing(table: String, column: String, definition: String) throws {
        guard let db = db else { return }
        let existingColumns = try SQLiteSafeQuery.rows(db.prepare("PRAGMA table_info(\(table))")).compactMap { row -> String? in
            row[1] as? String
        }
        guard !existingColumns.contains(column) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
    
    /// Reset database (for testing)
    func reset() throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        // Drop all tables
        try db.execute("DROP TABLE IF EXISTS undo_stack")
        try db.execute("DROP TABLE IF EXISTS file_changes")
        try db.execute("DROP TABLE IF EXISTS tool_calls")
        try db.execute("DROP TABLE IF EXISTS message_parts")
        try db.execute("DROP TABLE IF EXISTS messages")
        try db.execute("DROP TABLE IF EXISTS sessions")
        try db.execute("DROP TABLE IF EXISTS projects")
        try db.execute("DROP TABLE IF EXISTS providers")
        try db.execute("DROP TABLE IF EXISTS schema_version")
        try db.execute("DROP TABLE IF EXISTS messages_fts")
        
        // Recreate
        try createTables()
        try createIndexes()
        try createFTS5Index()
        try runMigrationsIfNeeded()
    }

    /// Close the live connection and drop it, so the on-disk file is no longer
    /// held by an open handle. Part of the "clear app cache" reset — deleting a
    /// DB file underneath an open connection orphans the inode and makes every
    /// later statement fail with "attempt to write a readonly database" (and,
    /// because SQLite.swift force-unwraps step errors during iteration, that
    /// used to crash the process with SIGILL). After `disconnectForReset`, the
    /// file can be removed cleanly and `reopenAfterReset` builds a fresh one.
    func disconnectForReset() {
        // SQLite.swift's `Connection` closes the handle in `deinit`, so
        // releasing the strong reference is the supported way to close it.
        db = nil
    }

    /// Reopen the database after a reset (creates a brand-new empty file at
    /// `dbPath`). No-op-safe when the connection is already gone.
    func reopenAfterReset() {
        guard db == nil else { return }
        initialize()
    }

    /// Full wipe: close the connection, delete the database file and its SQLite
    /// sidecars (`-journal`, `-wal`, `-shm`), then reopen a fresh empty
    /// database. This is the honest implementation of "clear app cache" — the
    /// file on disk is really gone and a clean one is recreated, instead of
    /// dropping tables into an unlinked inode.
    func wipeAndReopen() throws {
        disconnectForReset()
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
        initialize()
        guard db != nil else { throw DatabaseError.notInitialized }
    }
    
    // MARK: - Maintenance
    
    func vacuum() throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.execute("VACUUM")
    }
}
