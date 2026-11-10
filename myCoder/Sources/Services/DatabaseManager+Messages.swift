import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Message Operations
    
    func insertMessage(
        id: String,
        sessionId: String,
        role: String,
        content: String,
        modelId: String? = nil,
        providerId: String? = nil,
        reasoning: String? = nil,
        usage: UsageCapture? = nil,
        metadata: String? = nil
    ) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let now = Int64(Date().timeIntervalSince1970)
        // Round 30: replace-on-conflict, mirroring ProjectDatabaseManager.
        // MessageStore.update() re-saves the SAME message id on every
        // streaming/status change; a plain INSERT threw
        // `UNIQUE constraint failed: messages.id`, so streamed assistant text
        // never reached this database (empty bubbles after history reload).
        try db.run(messages.insert(
            or: .replace,
            messageId <- id,
            messageSessionId <- sessionId,
            messageRole <- role,
            messageContent <- content,
            messageCreatedAt <- now,
            messageModelId <- modelId ?? usage?.modelID,
            messageProviderId <- providerId ?? usage?.providerID,
            messagePromptTokens <- usage.map { Int64($0.promptTokens) },
            messageCompletionTokens <- usage.map { Int64($0.completionTokens) },
            messageCostUsd <- usage?.costUSD,
            messageReasoning <- reasoning,
            messageMetadata <- metadata,
            messageIsFinished <- true
        ))

        if usage != nil {
            try recalculateSessionUsage(id: sessionId)
        }
        // Update session timestamp
        try updateSessionTimestamp(id: sessionId)
    }

    /// Update the usage columns of an already-stored message (e.g. when usage
    /// arrives only after the initial insert, at stream finish). Returns true if
    /// a row was updated, false if no message with that id exists.
    @discardableResult
    func updateMessageTokens(id: String, usage: UsageCapture) throws -> Bool {
        guard let db = db else { throw DatabaseError.notInitialized }
        let row = messages.filter(messageId == id)
        let count = try db.run(row.update(
            messagePromptTokens <- Int64(usage.promptTokens),
            messageCompletionTokens <- Int64(usage.completionTokens),
            messageCostUsd <- usage.costUSD,
            messageModelId <- usage.modelID,
            messageProviderId <- usage.providerID
        ))
        if count > 0, let sessionId = try db.pluck(row.select(messageSessionId))?[messageSessionId] {
            try updateSessionTimestamp(id: sessionId)
            try recalculateSessionUsage(id: sessionId)
        }
        return count > 0
    }

    /// Recompute and persist `tokens_used` / `cost_usd` for a session from the
    /// usage of its assistant messages. Call after any message usage change.
    func recalculateSessionUsage(id: String) throws {
        guard let db = db else { return }
        var tokens: Int64 = 0
        var cost: Double = 0
        var hasCost = false
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(
            messages.select(messagePromptTokens, messageCompletionTokens, messageCostUsd)
                .filter(messageSessionId == id && messageRole == "assistant"))) {
            tokens += (row[messagePromptTokens] ?? 0) + (row[messageCompletionTokens] ?? 0)
            if let c = row[messageCostUsd] {
                cost += c
                hasCost = true
            }
        }
        do {
            let count = try db.run(sessions.filter(sessionId == id).update(
                sessionTokensUsed <- tokens,
                sessionCostUsd <- hasCost ? cost : 0
            ))
            if count > 0 {
                try updateSessionTimestamp(id: id)
            }
        } catch {
            print("❌ recalculateSessionUsage failed for \(id): \(error)")
        }
    }

    func getMessagesBySession(sessionId: String, limit: Int? = nil, offset: Int = 0) throws -> [MessageRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        var query = messages.filter(messageSessionId == sessionId).order(messageCreatedAt.asc)
        if let limit = limit {
            query = query.limit(limit, offset: offset)
        }
        
        var results: [MessageRecord] = []
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(query)) {
            results.append(MessageRecord(
                id: row[messageId],
                sessionId: row[messageSessionId],
                role: row[messageRole],
                content: row[messageContent],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[messageCreatedAt])),
                reasoning: row[messageReasoning],
                isFinished: row[messageIsFinished],
                modelId: row[messageModelId],
                providerId: row[messageProviderId],
                promptTokens: row[messagePromptTokens].map { Int($0) },
                completionTokens: row[messageCompletionTokens].map { Int($0) },
                costUsd: row[messageCostUsd],
                metadata: row[messageMetadata]
            ))
        }
        return results
    }
    
    func insertMessagePart(
        id: String,
        messageId: String,
        type: String,
        content: String? = nil,
        toolName: String? = nil,
        toolArgs: String? = nil,
        toolResult: String? = nil,
        toolCallId: String? = nil,
        sequenceOrder: Int
    ) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        // OR REPLACE: a message is saved on every streaming/status update, so
        // a part with a stable id (tool callID) is re-inserted repeatedly — a
        // plain INSERT fails with UNIQUE constraint and the update (e.g. the
        // tool RESULT folding into the part) is silently lost.
        try db.run(messageParts.insert(
            or: .replace,
            partId <- id,
            partMessageId <- messageId,
            partType <- type,
            partContent <- content,
            partToolName <- toolName,
            partToolArgs <- toolArgs,
            partToolResult <- toolResult,
            partToolCallId <- toolCallId,
            partSequenceOrder <- Int64(sequenceOrder)
        ))
    }

    /// Delete all stored parts of a message: a message is re-saved on every
    /// update, so stale part rows (removed from the in-memory set) must not
    /// survive alongside the fresh insert.
    func deleteMessageParts(messageId: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(messageParts.filter(partMessageId == messageId).delete())
    }

    /// Delete one message row and its parts from the global store. Used when
    /// a message is moved into the owning project database.
    func deleteMessage(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(messageParts.filter(partMessageId == id).delete())
        try db.run(messages.filter(messageId == id).delete())
    }

    func getMessageParts(messageId: String) throws -> [MessagePartRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }

        let query = messageParts.filter(partMessageId == messageId).order(partSequenceOrder.asc)
        
        var results: [MessagePartRecord] = []
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(query)) {
            results.append(MessagePartRecord(
                id: row[partId],
                messageId: row[partMessageId],
                type: row[partType],
                content: row[partContent],
                toolName: row[partToolName],
                toolArgs: row[partToolArgs],
                toolResult: row[partToolResult],
                toolCallId: row[partToolCallId],
                sequenceOrder: Int(row[partSequenceOrder])
            ))
        }
        return results
    }
    
    // MARK: - Full-Text Search
    
    func searchMessages(query: String, limit: Int = 50) throws -> [String] {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let sql = """
            SELECT messages.id FROM messages_fts
            JOIN messages ON messages.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        
        var messageIds: [String] = []
        for row in try SQLiteSafeQuery.rows(db.prepare(sql, [query, limit])) {
            if let id = row[0] as? String {
                messageIds.append(id)
            }
        }
        return messageIds
    }
}
