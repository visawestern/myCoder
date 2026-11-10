import Foundation
import SQLite

extension ProjectDatabaseManager {
    // MARK: - Session Operations

    func insertSession(
        id: String,
        title: String,
        directory: String,
        branch: String? = nil,
        agentMode: String = "build",
        modelId: String? = nil,
        providerId: String? = nil,
        parentSessionId: String? = nil,
        subagentStatus: String? = nil,
        sessionGoal: String? = nil
    ) throws {
        let sessionGoalValue = sessionGoal
        let subagentStatusValue = subagentStatus
        touch()
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(sessions.insert(
            or: .replace,
            sessionId <- id,
            sessionTitle <- title,
            sessionCreatedAt <- now,
            sessionUpdatedAt <- now,
            sessionDirectory <- directory,
            sessionBranch <- branch,
            sessionAgentMode <- agentMode,
            sessionModelId <- modelId,
            sessionProviderId <- providerId,
            sessionParentId <- parentSessionId,
            sessionSubagentStatus <- subagentStatusValue,
            sessionIsArchived <- false,
            self.sessionGoal <- sessionGoalValue
        ))
    }

    /// Sub-agent chats spawned by `parentId`, newest first.
    func childSessions(parentId: String) throws -> [ProjectSessionRecord] {
        touch()
        return try SQLiteSafeQuery.rows(
            db.prepareRowIterator(sessions.filter(sessionParentId == parentId).order(sessionCreatedAt.asc))
        ).map(rowToSessionRecord)
    }

    /// Persist a sub-agent lifecycle status ("running" | "done" | "failed").
    func setSubagentStatus(id: String, status: String?) throws {
        touch()
        try db.run(sessions.filter(sessionId == id).update(sessionSubagentStatus <- status))
    }

    func getAllSessions(includeArchived: Bool = true) throws -> [ProjectSessionRecord] {
        touch()
        var query = sessions.order(sessionUpdatedAt.desc)
        if !includeArchived {
            query = sessions.filter(sessionIsArchived == false).order(sessionUpdatedAt.desc)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map(rowToSessionRecord)
    }

    /// True when this project store owns the given session id. Used to
    /// discover the owning project of a session whose in-memory route was
    /// lost (app restart) and no durable route row exists yet.
    func hasSession(id: String) throws -> Bool {
        touch()
        return try db.scalar(sessions.filter(sessionId == id).count) > 0
    }

    /// Persists the /goal value inside this project's database.
    /// nil clears the goal without touching unrelated session metadata.
    func setSessionGoal(id: String, goal: String?) throws {        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionGoal <- goal))
    }

    func updateSessionTimestamp(id: String) throws {
        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionUpdatedAt <- Int64(Date().timeIntervalSince1970)))
    }

    /// Persist the model and provider a chat uses, so reopening the chat
    /// restores the same selection.
    @discardableResult
    func updateSessionModel(id: String, modelId: String?, providerId: String?) throws -> Int {
        touch()
        let row = sessions.filter(sessionId == id)
        return try db.run(row.update(
            sessionModelId <- modelId,
            sessionProviderId <- providerId
        ))
    }

    /// Rename a session in this project store (sidebar context menu).
    /// Returns the number of rows updated so callers can detect a stale id
    /// instead of reporting success for a silent no-op.
    @discardableResult
    func updateSessionTitle(id: String, title: String) throws -> Int {
        touch()
        let row = sessions.filter(sessionId == id)
        return try db.run(row.update(
            sessionTitle <- title,
            sessionUpdatedAt <- Int64(Date().timeIntervalSince1970)
        ))
    }

    /// Hard-delete one session. SQLite foreign keys are OFF by default on the
    /// pooled connection, so dependents are deleted explicitly (schema FKs are
    /// declared but cannot be relied on here); without this, messages orphaned
    /// and a later session reusing the id would show stale history.
    @discardableResult
    func deleteSession(id: String) throws -> Bool {
        touch()
        let messageIDs = try SQLiteSafeQuery.rows(
            db.prepareRowIterator(messages.filter(messageSessionId == id).select(messageId))
        ).map { $0[messageId] }
        if !messageIDs.isEmpty {
            let callIDs = try SQLiteSafeQuery.rows(
                db.prepareRowIterator(toolCalls.filter(messageIDs.contains(toolCallMessageId)).select(toolCallId))
            ).map { $0[toolCallId] }
            if !callIDs.isEmpty {
                try db.run(fileChanges.filter(callIDs.contains(fileChangeToolCallId)).delete())
            }
            try db.run(toolCalls.filter(messageIDs.contains(toolCallMessageId)).delete())
            try db.run(messageParts.filter(messageIDs.contains(partMessageId)).delete())
            try db.run(messages.filter(messageIDs.contains(messageId)).delete())
        }
        try db.run(undoStack.filter(undoSessionId == id).delete())
        try db.run(requestHistory.filter(requestHistorySessionId == id).delete())
        return try db.run(sessions.filter(sessionId == id).delete()) > 0
    }

    func archiveSession(id: String) throws {
        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionIsArchived <- true))
    }

    func unarchiveSession(id: String) throws {
        touch()
        // Only an actually archived session changes state; otherwise every
        // chat click would bump `updated_at` and reorder the sidebar.
        //
        // The condition lives in the UPDATE itself: a separate read would
        // crash on a missing row or a NULL `is_archived` (SQLite.swift force
        // unwraps the scalar binding) and would race with a concurrent write.
        try db.run(
            "UPDATE sessions SET is_archived = 0, updated_at = ? WHERE id = ? AND is_archived IS NOT 0",
            Int64(Date().timeIntervalSince1970),
            id
        )
    }

    /// Archives active sessions older than the supplied age in this project DB.
    @discardableResult
    func archiveSessionsOlderThan(days: Int, now: Date = Date()) throws -> Int {
        touch()
        let cutoff = Int64(now.timeIntervalSince1970) - Int64(max(0, days) * 86400)
        let oldActive = sessions.filter(sessionIsArchived == false && sessionUpdatedAt < cutoff)
        return try db.run(oldActive.update(sessionIsArchived <- true))
    }

    /// Permanently deletes every archived session in this project DB.
    @discardableResult
    func deleteArchivedSessions() throws -> Int {
        touch()
        return try db.run(sessions.filter(sessionIsArchived == true).delete())
    }

    /// Permanently deletes sessions older than the supplied age in this project DB.
    @discardableResult
    func deleteSessionsOlderThan(days: Int, now: Date = Date()) throws -> Int {
        touch()
        let cutoff = Int64(now.timeIntervalSince1970) - Int64(max(0, days) * 86400)
        return try db.run(sessions.filter(sessionUpdatedAt < cutoff).delete())
    }

    func rowToSessionRecord(_ row: Row) -> ProjectSessionRecord {
        ProjectSessionRecord(
            id: row[sessionId],
            title: row[sessionTitle],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row[sessionCreatedAt])),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row[sessionUpdatedAt])),
            directory: row[sessionDirectory],
            branch: row[sessionBranch],
            agentMode: row[sessionAgentMode],
            isArchived: row[sessionIsArchived],
            tokensUsed: Int(row[sessionTokensUsed]),
            costUsd: row[sessionCostUsd],
            sessionGoal: row[sessionGoal],
            modelId: row[sessionModelId],
            providerId: row[sessionProviderId],
            parentSessionId: row[sessionParentId],
            subagentStatus: row[sessionSubagentStatus]
        )
    }
}
