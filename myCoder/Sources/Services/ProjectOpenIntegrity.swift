import Foundation
import SQLite

/// Result of an open-time integrity check (plan Раздел 8 п.48).
enum ProjectOpenIntegrityResult: Equatable {
    case ok
    /// The database file exists but could not be read/validated.
    case corrupt(String)
}

/// Presented when a project's database fails its open-time integrity check.
/// Identifiable so SwiftUI can drive an `.alert(item:)` offer to restore.
struct ProjectIntegrityAlert: Identifiable, Equatable {
    let id = UUID()
    let projectPath: String
    let message: String
}

/// Open-time integrity checking + restore-from-backup (E04, plan Раздел 8 п.48).
/// Runs on every project open: a corrupted `project.db` must be detected at
/// open time (not silently crash or serve stale data), and the newest auto
/// backup must be offered for restore. Foundation-only + real SQLite so it is
/// fully testable against temp project directories.
enum ProjectOpenIntegrity {

    /// Verifies the project's database at open time. A missing database file
    /// is NOT corruption (first open creates it). When the file exists but
    /// cannot be opened/validated, `.corrupt` carries the underlying reason.
    static func checkOnOpen(projectPath: String) -> ProjectOpenIntegrityResult {
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return .ok }
        // A 0-byte file is "not yet created", not corruption.
        guard let size = fileSize(dbURL), size > 0 else { return .ok }
        // Header check: a valid SQLite db starts with the 16-byte magic
        // "SQLite format 3\0". A non-empty file without the magic (garbage,
        // truncated, wrong format) is corrupt. This is exactly how SQLite
        // detects SQLITE_NOTADB, but done by reading the file directly —
        // deterministically and pool-state-free — because a read-only
        // `Connection` on a short/garbage file can mask it as an "empty" db
        // and report a clean integrity check.
        guard hasSQLiteMagic(at: dbURL) else { return .corrupt("not a SQLite database file") }
        do {
            let connection = try Connection(dbURL.path, readonly: true)
            let corruption = try ProjectDatabaseManager.integrityQuickCheck(on: connection)
            return corruption == nil ? .ok : .corrupt(corruption!)
        } catch {
            return .corrupt(error.localizedDescription)
        }
    }

    /// On-disk size of `url`, or nil when unreadable.
    private static func fileSize(_ url: URL) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.size] as? UInt64
    }

    /// `true` iff the first 16 bytes of `url` equal the SQLite magic header
    /// (`"SQLite format 3\0"`). The cheapest correct corruption signal.
    private static func hasSQLiteMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16) else { return false }
        let magic: [UInt8] = [
            0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
            0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00
        ]
        return Array(header) == magic
    }

    /// Restores the newest auto-backup over the (corrupt) `project.db`.
    /// Drops the pooled connection first so the restored file is read fresh,
    /// and removes stale `-journal`/`-wal` sidecars that could replay old
    /// garbage. Returns the backup URL, or nil when no backup exists.
    @discardableResult
    static func restoreLatestBackup(projectPath: String) throws -> URL? {
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        guard let newest = try ProjectAutoBackupLogic.listBackups(projectPath: projectPath).first else {
            return nil
        }
        let dbURL = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        // Remove the corrupt file and its sidecars so SQLite starts clean.
        for sidecar in [dbURL, dbURL.appendingPathExtension("journal"), dbURL.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: sidecar)
        }
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: newest, to: dbURL)
        return newest
    }
}
