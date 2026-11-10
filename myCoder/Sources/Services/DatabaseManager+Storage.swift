import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Raw SQL Execution (for undo stack и других операций)
    
    /// Выполнить raw SQL запрос (INSERT/UPDATE/DELETE)
    func exec(_ sql: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.execute(sql)
    }
    
    /// Выполнить raw SQL запрос и вернуть результаты
    func query(_ sql: String) throws -> [[Any]] {
        guard let db = db else { throw DatabaseError.notInitialized }
        var results: [[Any]] = []
        for row in try SQLiteSafeQuery.rows(db.prepare(sql)) {
            results.append(row as [Any])
        }
        return results
    }
    
    func getLastVacuumDate() -> Date? {
        UserDefaults.standard.object(forKey: "lastDatabaseVacuum") as? Date
    }
    
    func setLastVacuumDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "lastDatabaseVacuum")
    }
    
    func performMaintenanceIfNeeded() {
        queue.async {
            // Vacuum
            if let lastVacuum = self.getLastVacuumDate() {
                let daysSinceVacuum = Date().timeIntervalSince(lastVacuum) / 86400
                if daysSinceVacuum > 7 {
                    try? self.vacuum()
                    self.setLastVacuumDate(Date())
                }
            } else {
                try? self.vacuum()
                self.setLastVacuumDate(Date())
            }
            
            // Auto-archive sessions older than 7 days
            try? self.archiveSessionsOlderThan(days: 7)
        }
    }
    
    // MARK: - Storage Management
    
    /// Archive sessions not updated in more than `days` days
    func archiveSessionsOlderThan(days: Int) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(max(0, days) * 86400)
        let oldSessions = sessions.filter(sessionUpdatedAt < cutoff && sessionIsArchived == false)
        try db.run(oldSessions.update(sessionIsArchived <- true))
    }
    
    /// Unarchive a session
    func unarchiveSession(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        // Only an actually archived session changes state. Touching
        // `updated_at` for an already active session made every chat click
        // reorder the sidebar (the chat jumped to the top of the list).
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
    
    /// Hard delete all archived sessions and their messages
    func deleteArchivedSessions() throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        let archived = sessions.filter(sessionIsArchived == true)
        let count = try db.run(archived.delete())
        return count
    }

    /// Hard delete one session and its messages. Foreign keys are OFF by
    /// SQLite default, so dependents are removed explicitly (schema FKs alone
    /// leave orphaned messages/parts behind).
    @discardableResult
    func deleteSession(id: String) throws -> Bool {
        guard let db = db else { throw DatabaseError.notInitialized }
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
        return try db.run(sessions.filter(sessionId == id).delete()) > 0
    }
    
    /// Hard delete sessions older than N days (including their messages via FK cascade)
    func deleteSessionsOlderThan(days: Int) throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(max(0, days) * 86400)
        let old = sessions.filter(sessionUpdatedAt < cutoff)
        let count = try db.run(old.delete())
        return count
    }
    
    /// Count messages in the database
    func messageCount() throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.scalar(messages.count)
    }

    /// Count messages of one session. Used for tail-paging the history
    /// (newest-N initial load + older pages) without fetching everything.
    func countMessages(sessionId sessionIdValue: String) throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.scalar(messages.filter(messageSessionId == sessionIdValue).count)
    }

    /// User messages that carry visible text — the unit the chat navigator
    /// numbers across the whole session.
    func countUserMessages(sessionId sessionIdValue: String) throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        let query = messages.filter(
            messageSessionId == sessionIdValue &&
            messageRole == "user" &&
            messageContent != ""
        )
        return try db.scalar(query.count)
    }

    /// Read real per-message usage data points for statistics (plan Раздел 10
    /// Блок 2 п.13-14). Uses the existing model_id/provider_id/prompt_tokens/
    /// completion_tokens/cost_usd columns. costUSD is nil only when the
    /// provider reported no cost (local).
    func usageDataPoints() throws -> [UsageDataPoint] {
        guard let db = db else { throw DatabaseError.notInitialized }
        var points: [UsageDataPoint] = []
        let query = messages.filter(messageRole == "assistant")
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(query)) {
            let prompt = Int(row[messagePromptTokens] ?? 0)
            let completion = Int(row[messageCompletionTokens] ?? 0)
            guard prompt > 0 || completion > 0 else { continue }
            let model = row[messageModelId] ?? "unknown"
            let provider = row[messageProviderId] ?? "unknown"
            let ts = Date(timeIntervalSince1970: TimeInterval(row[messageCreatedAt]))
            points.append(UsageDataPoint(
                timestamp: ts, model: model, provider: provider,
                promptTokens: prompt, completionTokens: completion, costUSD: row[messageCostUsd]
            ))
        }
        return points
    }
    
    /// Count sessions per project
    func sessionCountsByProject() throws -> [(projectId: String, active: Int, archived: Int)] {
        guard let db = db else { throw DatabaseError.notInitialized }
        var results: [(String, Int, Int)] = []
        // Active
        for row in try SQLiteSafeQuery.rows(db.prepare("SELECT project_id, COUNT(*) FROM sessions WHERE is_archived = 0 GROUP BY project_id")) {
            if let pid = row[0] as? String, let count = row[1] as? Int64 {
                results.append((pid, Int(count), 0))
            }
        }
        // Archived
        for row in try SQLiteSafeQuery.rows(db.prepare("SELECT project_id, COUNT(*) FROM sessions WHERE is_archived = 1 GROUP BY project_id")) {
            if let pid = row[0] as? String, let count = row[1] as? Int64 {
                if let idx = results.firstIndex(where: { $0.0 == pid }) {
                    results[idx] = (pid, results[idx].1, Int(count))
                } else {
                    results.append((pid, 0, Int(count)))
                }
            }
        }
        return results
    }
    
    /// Total database file size in bytes
    func databaseFileSize() -> UInt64 {
        guard !isInMemory else { return 0 }
        let path = dbPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return 0 }
        return (attrs[.size] as? UInt64) ?? 0
    }
}
