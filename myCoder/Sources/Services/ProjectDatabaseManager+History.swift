import Foundation
import SQLite

extension ProjectDatabaseManager {
    // MARK: - Request History (non-chat operations: file edits, commands, applied tool calls)

    func recordRequestHistory(sessionId sessionIdValue: String?, type: String, payload: String) throws {
        touch()
        try db.run(requestHistory.insert(
            requestHistoryId <- UUID().uuidString,
            requestHistorySessionId <- sessionIdValue,
            requestHistoryType <- type,
            requestHistoryPayload <- payload,
            requestHistoryCreatedAt <- Int64(Date().timeIntervalSince1970)
        ))
    }

    func getRequestHistory(sessionId sessionIdValue: String? = nil, limit: Int? = 200) throws -> [ProjectRequestHistoryRecord] {
        touch()
        var base = requestHistory
        if let sessionIdValue {
            base = base.filter(requestHistorySessionId == sessionIdValue)
        }
        var query = base.order(requestHistoryCreatedAt.asc)
        if let limit {
            query = base.order(requestHistoryCreatedAt.asc).limit(limit)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectRequestHistoryRecord(
                id: row[requestHistoryId],
                sessionId: row[requestHistorySessionId],
                type: row[requestHistoryType],
                payload: row[requestHistoryPayload],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[requestHistoryCreatedAt]))
            )
        }
    }

    // MARK: - Undo Stack (point-in-time, per-entry rollback)

    func insertUndoEntry(
        id: String,
        sessionId sessionIdValue: String,
        actionType: String,
        targetPath: String?,
        snapshotId: String?,
        metadata: String? = nil
    ) throws {
        touch()
        try db.run(undoStack.insert(
            or: .replace,
            undoId <- id,
            undoSessionId <- sessionIdValue,
            undoActionType <- actionType,
            undoTargetPath <- targetPath,
            undoSnapshotId <- snapshotId,
            undoMetadata <- metadata,
            undoCreatedAt <- Int64(Date().timeIntervalSince1970),
            undoCanUndo <- true
        ))
    }

    /// Returns undo entries newest-first, matching how a rollback list is
    /// presented to the user (most recent action on top).
    func getUndoStack(sessionId sessionIdValue: String, onlyUsable: Bool = false) throws -> [ProjectUndoEntryRecord] {
        touch()
        var query = undoStack.filter(undoSessionId == sessionIdValue)
        if onlyUsable {
            query = query.filter(undoCanUndo == true)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query.order(undoCreatedAt.desc))).map { row in
            ProjectUndoEntryRecord(
                id: row[undoId],
                sessionId: row[undoSessionId],
                actionType: row[undoActionType],
                targetPath: row[undoTargetPath],
                snapshotId: row[undoSnapshotId],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[undoCreatedAt])),
                canUndo: row[undoCanUndo]
            )
        }
    }

    /// Marks a specific undo entry as consumed (soft delete), independent of
    /// every other entry — this is what makes point-in-time (not just
    /// "undo everything") rollback possible.
    func markUndoEntryUsed(id: String) throws {
        touch()
        let row = undoStack.filter(undoId == id)
        try db.run(row.update(undoCanUndo <- false))
    }

    func getUndoEntry(id: String) throws -> ProjectUndoEntryRecord? {
        touch()
        guard let row = try db.pluck(undoStack.filter(undoId == id)) else { return nil }
        return ProjectUndoEntryRecord(
            id: row[undoId],
            sessionId: row[undoSessionId],
            actionType: row[undoActionType],
            targetPath: row[undoTargetPath],
            snapshotId: row[undoSnapshotId],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row[undoCreatedAt])),
            canUndo: row[undoCanUndo]
        )
    }

    // MARK: - Full-Text Search

    func searchMessages(query: String, limit: Int = 50) throws -> [String] {
        touch()
        let sql = """
            SELECT messages.id FROM messages_fts
            JOIN messages ON messages.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var ids: [String] = []
        for row in try SQLiteSafeQuery.rows(db.prepare(sql, [query, limit])) {
            if let id = row[0] as? String {
                ids.append(id)
            }
        }
        return ids
    }
}
