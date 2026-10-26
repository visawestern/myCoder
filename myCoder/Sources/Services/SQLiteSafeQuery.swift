import Foundation
import SQLite

/// Safe row iteration for SQLite.swift `Statement`.
///
/// `for row in try db.prepare(...)` looks like it propagates errors, but it
/// relies on SQLite.swift's `Sequence` conformance, whose `next()` is
/// `try! failableNext()` (see `Statement.swift`). Any SQLite error raised
/// MID-iteration — a busy connection, a database file deleted underneath the
/// open handle (which makes every later statement fail with "attempt to write
/// a readonly database"), or page corruption — crashes the whole process with
/// SIGILL instead of throwing a catchable error. This helper steps the
/// statement with the throwing `failableNext()` and surfaces those errors
/// normally, so the app can degrade instead of dying.
enum SQLiteSafeQuery {
    /// Drain a prepared statement into its rows, propagating SQLite errors.
    static func rows(_ statement: Statement) throws -> [[Binding?]] {
        var result: [[Binding?]] = []
        while let row = try statement.failableNext() {
            result.append(row)
        }
        return result
    }

    /// Drain a typed `QueryType` into its rows, propagating SQLite errors.
    ///
    /// `Connection.prepare(_ query:)` returns an `AnySequence<Row>` whose
    /// iterator calls the force-unwrapping `Statement.next()`, so typed
    /// iteration was just as fatal. `prepareRowIterator` exposes the throwing
    /// `failableNext()` instead, which this helper steps safely.
    static func rows(_ rowIterator: RowIterator) throws -> [Row] {
        var result: [Row] = []
        while let row = try rowIterator.failableNext() {
            result.append(row)
        }
        return result
    }
}
