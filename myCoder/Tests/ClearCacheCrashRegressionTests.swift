import XCTest
import SQLite
@testable import myCoder

/// Regression tests for the "Clear app cache" crash
/// (`myCoder-2026-08-05-220402.ips`: SIGILL in SQLite.swift
/// `FailableIterator.next()` → `DatabaseManager.sessionCountsByProject()`).
///
/// Root cause: `resetStorage(.appCacheOnly)` deleted `~/.mycoder/mimo.db`
/// underneath the still-open `DatabaseManager.shared` connection. The orphaned
/// handle keeps running; the next `SELECT` fails with a real SQLite error
/// (`disk I/O error` / `attempt to write a readonly database`) — but
/// SQLite.swift's `Statement.next()` is `try!`, so that error became a hard
/// process kill instead of a catchable throw.
///
/// These tests pin the two halves of the fix:
///  1. `SQLiteSafeQuery` steps statements with `failableNext()`, so the
///     orphaned-file SELECT *throws* instead of SIGILling.
///  2. The wipe-and-reopen recipe (drop the connection, delete the file +
///     sidecars, reopen) yields a working fresh database — which is what
///     `AppState.resetStorage` now does via `DatabaseManager.wipeAndReopen()`.
final class ClearCacheCrashRegressionTests: XCTestCase {

    private func makeSandbox() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clear-cache-crash-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Build the exact precondition of the crash report: a database (DELETE
    /// journal mode — the mode `DatabaseManager` actually uses) whose main
    /// file is removed underneath the still-open connection.
    private func makeOrphanedConnection(in dir: URL) throws -> Connection {
        let conn = try Connection(dir.appendingPathComponent("mimo.db").path)
        try conn.execute("CREATE TABLE sessions (id TEXT, is_archived INTEGER)")
        try conn.execute("INSERT INTO sessions VALUES ('s1', 0)")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("mimo.db"))
        return conn
    }

    func testOrphanedSelectThrowsInsteadOfCrashing() throws {
        let dir = makeSandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let conn = try makeOrphanedConnection(in: dir)

        // What `DatabaseManager.reset()` does after the file was deleted: the
        // DROP fails with "attempt to write a readonly database" — silently
        // swallowed by the `try?` in the resetStorage closure.
        do {
            try conn.execute("DROP TABLE sessions")
            XCTFail("DROP on an orphaned connection should have failed")
        } catch {
            // expected
        }

        // Regression point: `prepare` still succeeds (the schema is cached),
        // so the pre-fix code reached the iterator — and `try!` turned the
        // step error into SIGILL here. The safe helper must throw instead.
        let stmt = try conn.prepare("SELECT COUNT(*) FROM sessions GROUP BY is_archived")
        XCTAssertThrowsError(try SQLiteSafeQuery.rows(stmt))
    }

    func testWipeAndReopenRecipeYieldsWorkingDatabase() throws {
        let dir = makeSandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("mimo.db").path
        var conn: Connection? = try Connection(path)
        try conn?.execute("CREATE TABLE sessions (id TEXT, is_archived INTEGER)")
        try conn?.execute("INSERT INTO sessions VALUES ('s1', 0)")
        try FileManager.default.removeItem(atPath: path)

        // Recovery recipe of `DatabaseManager.wipeAndReopen()`:
        // 1. drop the stale connection (deinit closes the orphaned handle),
        // 2. delete the file + sidecars,
        // 3. reopen a fresh empty database.
        conn = nil
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }

        let fresh = try Connection(path)
        try fresh.execute("CREATE TABLE sessions (id TEXT, is_archived INTEGER)")
        try fresh.execute("INSERT INTO sessions VALUES ('s1', 0)")
        XCTAssertEqual(try fresh.prepare("SELECT COUNT(*) FROM sessions").next()?[0] as? Int64, 1)
    }

    func testInMemoryWipeAndReopenKeepsWorking() throws {
        // End-to-end through the real DatabaseManager on the throwaway
        // in-memory database: disconnect + reopen must leave a usable DB.
        let manager = DatabaseManager(inMemory: true)
        try manager.wipeAndReopen()
        try manager.insertProject(id: "/tmp/wipe-reopen", name: "Wipe", path: "/tmp/wipe-reopen")
        XCTAssertEqual(try manager.getAllProjects().count, 1)
    }
}
