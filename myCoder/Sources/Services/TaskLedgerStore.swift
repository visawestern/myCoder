import Foundation
import SQLite

/// Persists one task ledger per session. The ledger is stored as JSON so the
/// shape can grow without a column migration; the row itself is small and read
/// once per send.
struct TaskLedgerStore {
    let db: Connection

    private static let ledgers = Table("task_ledgers")
    private static let sessionID = Expression<String>("session_id")
    private static let projectID = Expression<String>("project_id")
    private static let payload = Expression<String>("payload_json")
    private static let updatedAt = Expression<Int64>("updated_at")

    /// Idempotent: an existing project database gains the table on first use.
    static func createSchema(_ db: Connection) throws {
        try db.run(ledgers.create(ifNotExists: true) { table in
            table.column(sessionID, primaryKey: true)
            table.column(projectID)
            table.column(payload)
            table.column(updatedAt)
        })
        try db.run(ledgers.createIndex(updatedAt, ifNotExists: true))
    }

    func save(_ ledger: TaskLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TaskLedgerStoreError.encodingFailed
        }
        try db.run(Self.ledgers.insert(or: .replace,
                                       Self.sessionID <- ledger.sessionID,
                                       Self.projectID <- ledger.projectPath,
                                       Self.payload <- json,
                                       Self.updatedAt <- ledger.updatedAt))
    }

    func load(sessionID ledgerSessionID: String) throws -> TaskLedger? {
        guard let row = try db.pluck(Self.ledgers.filter(Self.sessionID == ledgerSessionID)) else {
            return nil
        }
        guard let data = row[Self.payload].data(using: .utf8) else {
            throw TaskLedgerStoreError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(TaskLedger.self, from: data)
        } catch {
            throw TaskLedgerStoreError.decodingFailed
        }
    }

    @discardableResult
    func delete(sessionID ledgerSessionID: String) throws -> Bool {
        try db.run(Self.ledgers.filter(Self.sessionID == ledgerSessionID).delete()) > 0
    }

    func count() throws -> Int {
        try db.scalar(Self.ledgers.count)
    }

    // MARK: - Loading for a send

    static func load(projectPath: String, sessionID: String) throws -> TaskLedger? {
        guard !projectPath.isEmpty, !sessionID.isEmpty else { return nil }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        return try manager.makeLedgerStore().load(sessionID: sessionID)
    }

    static func save(_ ledger: TaskLedger) throws {
        guard !ledger.projectPath.isEmpty else { throw TaskLedgerStoreError.noProject }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: ledger.projectPath)
        try manager.makeLedgerStore().save(ledger)
    }
}

enum TaskLedgerStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case noProject

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not encode the task ledger"
        case .decodingFailed: return "Could not decode the stored task ledger"
        case .noProject: return "The task ledger has no project to live in"
        }
    }
}
