import Foundation
import SQLite

extension ProjectDatabaseManager {
    // MARK: - Message Operations

    func insertMessage(
        id: String,
        sessionId sessionIdValue: String,
        role: String,
        content: String,
        modelId: String? = nil,
        providerId: String? = nil,
        reasoning: String? = nil,
        isFinished: Bool = true,
        usage: UsageCapture? = nil,
        createdAt: Date? = nil
    ) throws {
        touch()
        let now = Int64(createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        try db.run(messages.insert(
            or: .replace,
            messageId <- id,
            messageSessionId <- sessionIdValue,
            messageRole <- role,
            messageContent <- content,
            messageCreatedAt <- now,
            messageModelId <- modelId ?? usage?.modelID,
            messageProviderId <- providerId ?? usage?.providerID,
            messagePromptTokens <- usage.map { Int64($0.promptTokens) },
            messageCompletionTokens <- usage.map { Int64($0.completionTokens) },
            messageCostUsd <- usage?.costUSD,
            messageReasoning <- reasoning,
            messageIsFinished <- isFinished
        ))
        if usage != nil {
            try recalculateSessionUsage(id: sessionIdValue)
        }
        try updateSessionTimestamp(id: sessionIdValue)
    }

    /// Update usage columns of an already-stored message. Returns true if a row
    /// was updated. No-op (returns false) when the message id is unknown.
    @discardableResult
    func updateMessageTokens(id: String, usage: UsageCapture) throws -> Bool {
        touch()
        let row = messages.filter(messageId == id)
        let count = try db.run(row.update(
            messagePromptTokens <- Int64(usage.promptTokens),
            messageCompletionTokens <- Int64(usage.completionTokens),
            messageCostUsd <- usage.costUSD,
            messageModelId <- usage.modelID,
            messageProviderId <- usage.providerID
        ))
        if count > 0, let sid = try db.pluck(row.select(messageSessionId))?[messageSessionId] {
            try updateSessionTimestamp(id: sid)
            try recalculateSessionUsage(id: sid)
        }
        return count > 0
    }

    /// Recompute and persist `tokens_used` / `cost_usd` for a session from its
    /// assistant messages. Call after any message usage change.
    func recalculateSessionUsage(id: String) throws {
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
        let _ = try db.run(sessions.filter(sessionId == id).update(
            sessionTokensUsed <- tokens,
            sessionCostUsd <- hasCost ? cost : 0
        ))
    }

    /// Read per-message usage data points for statistics from this project DB.
    func usageDataPoints() throws -> [UsageDataPoint] {
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

    func getMessages(sessionId sessionIdValue: String, limit: Int? = nil, offset: Int = 0) throws -> [ProjectMessageRecord] {
        touch()
        var query = messages.filter(messageSessionId == sessionIdValue).order(messageCreatedAt.asc)
        if let limit {
            query = query.limit(limit, offset: offset)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectMessageRecord(
                id: row[messageId],
                sessionId: row[messageSessionId],
                role: row[messageRole],
                content: row[messageContent],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[messageCreatedAt])),
                reasoning: row[messageReasoning],
                isFinished: row[messageIsFinished]
            )
        }
    }

    func insertMessagePart(
        id: String,
        messageId messageIdValue: String,
        type: String,
        content: String? = nil,
        toolName: String? = nil,
        toolArgs: String? = nil,
        toolResult: String? = nil,
        toolCallId: String? = nil,
        sequenceOrder: Int
    ) throws {
        touch()
        try db.run(messageParts.insert(
            or: .replace,
            partId <- id,
            partMessageId <- messageIdValue,
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
    func deleteMessageParts(messageId messageIdValue: String) throws {
        touch()
        try db.run(messageParts.filter(partMessageId == messageIdValue).delete())
    }

    func getMessageParts(messageId messageIdValue: String) throws -> [ProjectMessagePartRecord] {
        touch()
        let query = messageParts.filter(partMessageId == messageIdValue).order(partSequenceOrder.asc)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectMessagePartRecord(
                id: row[partId],
                messageId: row[partMessageId],
                type: row[partType],
                content: row[partContent],
                toolName: row[partToolName],
                toolArgs: row[partToolArgs],
                toolResult: row[partToolResult],
                toolCallId: row[partToolCallId],
                sequenceOrder: Int(row[partSequenceOrder])
            )
        }
    }
}
