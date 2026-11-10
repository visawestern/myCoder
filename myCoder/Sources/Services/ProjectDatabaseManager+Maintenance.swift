import Foundation
import SQLite
#if canImport(SQLite3)
import SQLite3
#endif

extension ProjectDatabaseManager {
    // MARK: - Maintenance

    func vacuum() throws {
        try db.execute("VACUUM")
    }

    /// `PRAGMA integrity_quick_check` — returns nil when the database is intact,
    /// or a description of the corruption otherwise (plan Раздел 8 п.48).
    /// Uses the raw SQLite C API: the SQLite.swift wrapper doesn't surface
    /// PRAGMA result rows, and quick_check returns no rows on a fresh DB.
    func integrityCheck() throws -> String? {
        try Self.integrityQuickCheck(on: db)
    }

    /// Read-only `PRAGMA integrity_quick_check` against a bare connection.
    /// Used by `ProjectOpenIntegrity.checkOnOpen` so the open-time corruption
    /// probe never routes through `openConnection` (which runs `createSchema()`
    /// + `PRAGMA journal_mode=WAL` and would re-initialize a corrupt/garbage
    /// file, masking the corruption — a data-loss bug). A fresh read-only
    /// connection validates the on-disk file as-is, deterministically and
    /// independently of the connection-pool state.
    static func integrityQuickCheck(on connection: Connection) throws -> String? {
        let handle = connection.handle
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(NSMutableString()).toOpaque())
        let sql = "PRAGMA integrity_quick_check"
        let rc = sqlite3_exec(handle, sql, { ctx, colCount, values, _ in
            let result = Unmanaged<NSMutableString>.fromOpaque(ctx!).takeUnretainedValue()
            var parts: [String] = []
            for i in 0..<Int(colCount) {
                if let c = values![i] { parts.append(String(cString: c)) }
            }
            result.append(parts.joined(separator: ","))
            return 0
        }, context, nil)
        let collected = Unmanaged<NSMutableString>.fromOpaque(context).takeRetainedValue() as String
        guard rc == SQLITE_OK else { return "integrity check failed (rc \(rc))" }
        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "ok" ? nil : trimmed
    }

    func databaseFileSizeBytes() -> UInt64 {
        func size(_ url: URL) -> UInt64 {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
            return (attrs[.size] as? UInt64) ?? 0
        }
        // WAL (E21): the main .db file stays at its page size while new writes
        // land in the -wal sidecar, so "real on-disk usage" = db + wal + shm.
        return size(databaseFileURL)
            + size(URL(fileURLWithPath: databaseFileURL.path + "-wal"))
            + size(URL(fileURLWithPath: databaseFileURL.path + "-shm"))
    }

    func sessionCount() throws -> Int {
        try db.scalar(sessions.count)
    }

    func messageCount() throws -> Int {
        try db.scalar(messages.count)
    }

    /// Count messages of one session. Used for tail-paging the history
    /// (newest-N initial load + older pages) without fetching everything.
    func countMessages(sessionId sessionIdValue: String) throws -> Int {
        touch()
        return try db.scalar(messages.filter(messageSessionId == sessionIdValue).count)
    }

    /// User messages that carry visible text. The chat navigator numbers the
    /// user's own messages, and the numbering must span the whole session —
    /// not only the page that is currently loaded.
    func countUserMessages(sessionId sessionIdValue: String) throws -> Int {
        touch()
        let query = messages.filter(
            messageSessionId == sessionIdValue &&
            messageRole == "user" &&
            messageContent != ""
        )
        return try db.scalar(query.count)
    }
}
