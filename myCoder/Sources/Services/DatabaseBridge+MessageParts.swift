import Foundation

extension DatabaseBridge {
    /// Сохранить часть сообщения через переданный project database inserter.
    func saveMessagePart(
        _ part: MessagePartContent,
        messageId: String,
        sequenceOrder: Int,
        insert: MessagePartInserter
    ) throws {
        // Stable part id: a tool call keeps its callID so repeated saves of
        // the same part REPLACE the row instead of stacking duplicates (an
        // update per streaming poll used to multiply parts ×N). Other part
        // types derive a deterministic id from their content.
        let partId: String
        switch part {
        case .toolCall(_, _, _, let callId):
            partId = callId ?? "\(messageId)-tool-\(sequenceOrder)"
        case .routeInfo:
            partId = "\(messageId)-route-\(sequenceOrder)"
        case .text(let text):
            partId = "\(messageId)-text-\(text.hashValue)-\(sequenceOrder)"
        case .reasoning(let text):
            partId = "\(messageId)-reasoning-\(text.hashValue)-\(sequenceOrder)"
        case .stepStart:
            partId = "\(messageId)-step-start-\(sequenceOrder)"
        case .stepFinish:
            partId = "\(messageId)-step-finish-\(sequenceOrder)"
        case .image(let base64, _):
            partId = "\(messageId)-image-\(base64.hashValue)-\(sequenceOrder)"
        case .compiledContext(let text):
            partId = "\(messageId)-compiled-context-\(text.hashValue)-\(sequenceOrder)"
        }

        switch part {
        case .text(let text):
            try insert(partId, messageId, "text", text, nil, nil, nil, nil, sequenceOrder)

        case .reasoning(let text):
            try insert(partId, messageId, "reasoning", text, nil, nil, nil, nil, sequenceOrder)

        case .toolCall(let name, let args, let result, let callId):
            try insert(partId, messageId, "tool_call", nil, name, args, result, callId, sequenceOrder)

        case .stepStart:
            try insert(partId, messageId, "step_start", nil, nil, nil, nil, nil, sequenceOrder)

        case .stepFinish:
            try insert(partId, messageId, "step_finish", nil, nil, nil, nil, nil, sequenceOrder)

        case .image(let base64, let mimeType):
            try insert(partId, messageId, "image", "\(mimeType)|\(base64)", nil, nil, nil, nil, sequenceOrder)

        case .routeInfo(let chips):
            let data = (try? JSONSerialization.data(withJSONObject: chips, options: []))
                ?? Data("[]".utf8)
            try insert(partId, messageId, "route_info",
                       String(data: data, encoding: .utf8) ?? "[]",
                       nil, nil, nil, nil, sequenceOrder)

        case .compiledContext(let text):
            try insert(partId, messageId, "compiled_context", text,
                       nil, nil, nil, nil, sequenceOrder)
        }
    }
    
    /// Delete one message (with its parts) from the program database. Used to
    /// roll back a compaction summary: the summary is a real message, so the
    /// rollback has to remove it from the store as well.
    func deleteMessage(id: String) {
        do {
            try db.deleteMessage(id: id)
        } catch {
            MyCoderAPIServer.appendLog("❌ Failed to delete message \(id): \(error)")
        }
    }

    /// Load messages from the program database.
    /// `offset` counts from the oldest row (ASC). The initial history load uses
    /// `loadMessageTail` — oldest-first + limit hides new messages as soon as a
    /// session outgrows the page size.
    func loadMessages(sessionId: String, limit: Int? = nil, offset: Int = 0) -> [Message] {
        do {
            let records = try db.getMessagesBySession(sessionId: sessionId, limit: limit, offset: offset)
            return records.map { record in
                let parts = (try? db.getMessageParts(messageId: record.id)) ?? []
                let metadata = MessageMetadataCodec.decode(record.metadata)
                return Message(
                    id: record.id,
                    role: stringToRole(record.role),
                    content: record.content,
                    isStreaming: false,
                    parts: parts.map { convertPartRecord($0) },
                    reasoning: record.reasoning ?? "",
                    isFinished: record.isFinished,
                    sendInfo: metadata.sendInfo,
                    contextSummary: metadata.contextSummary
                )
            }
        } catch {
            print("❌ Failed to load messages: \(error)")
            return []
        }
    }

    /// Total persisted messages of a session.
    func messageCount(sessionId: String) -> Int {
        (try? db.countMessages(sessionId: sessionId)) ?? 0
    }

    /// User messages with visible text in the whole session — the unit the
    /// chat navigator numbers, independent of the loaded history page.
    func userMessageCount(sessionId: String) -> Int {
        (try? db.countUserMessages(sessionId: sessionId)) ?? 0
    }

    /// Newest `take` messages in ASC display order (`nil` = all). The initial
    /// history load MUST use the tail: oldest-first + limit hides every new
    /// message once a session grows past the page size, and nothing can page
    /// to them afterwards.
    func loadMessageTail(sessionId: String, take: Int?) -> [Message] {
        guard let take else { return loadMessages(sessionId: sessionId, limit: nil) }
        let total = messageCount(sessionId: sessionId)
        let bounded = min(max(take, 0), total)
        guard bounded > 0 else { return [] }
        return loadMessages(sessionId: sessionId, limit: bounded, offset: total - bounded)
    }

    /// One older page preceding the currently displayed tail. `loadedCount` is
    /// how many messages are already shown. Returns the page (ASC) plus whether
    /// even older rows remain.
    func loadOlderPage(sessionId: String, loadedCount: Int, pageSize: Int) -> (messages: [Message], hasMore: Bool) {
        let total = messageCount(sessionId: sessionId)
        let olderCount = total - max(loadedCount, 0)
        guard olderCount > 0, pageSize > 0 else { return ([], false) }
        let take = min(pageSize, olderCount)
        let offset = olderCount - take
        let page = loadMessages(sessionId: sessionId, limit: take, offset: offset)
        return (page, offset > 0)
    }
    
    /// Shared conversion for every part-record shape (global + per-project
    /// DBs use identical column sets). Audit ARCH-09: the two previous
    /// converters were byte-identical — one canonical implementation now
    /// serves both call sites.
    private func convertPartFields(type: String,
                                   content: String?,
                                   toolName: String?,
                                   toolArgs: String?,
                                   toolResult: String?,
                                   toolCallId: String?) -> MessagePartContent {
        switch type {
        case "text":
            return .text(content ?? "")
        case "reasoning":
            return .reasoning(content ?? "")
        case "tool_call":
            return .toolCall(
                name: toolName ?? "",
                args: toolArgs ?? "{}",
                result: toolResult,
                callID: toolCallId
            )
        case "step_start":
            return .stepStart
        case "step_finish":
            return .stepFinish
        case "image":
            if let content {
                let parts = content.split(separator: "|", maxSplits: 1)
                let mimeType = parts.count > 0 ? String(parts[0]) : "image/png"
                let base64 = parts.count > 1 ? String(parts[1]) : ""
                return .image(base64: base64, mimeType: mimeType)
            }
            return .text("")
        case "route_info":
            if let content,
               let data = content.data(using: .utf8),
               let chips = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return .routeInfo(chips: chips)
            }
            return .routeInfo(chips: [])
        case "compiled_context":
            return .compiledContext(content ?? "")
        default:
            return .text("")
        }
    }

    /// Конвертировать MessagePartRecord (общая БД) в MessagePartContent
    private func convertPartRecord(_ record: MessagePartRecord) -> MessagePartContent {
        convertPartFields(type: record.type,
                          content: record.content,
                          toolName: record.toolName,
                          toolArgs: record.toolArgs,
                          toolResult: record.toolResult,
                          toolCallId: record.toolCallId)
    }

    /// Конвертировать ProjectMessagePartRecord (per-project БД) в MessagePartContent
    private func convertProjectPartRecord(_ record: ProjectMessagePartRecord) -> MessagePartContent {
        convertPartFields(type: record.type,
                          content: record.content,
                          toolName: record.toolName,
                          toolArgs: record.toolArgs,
                          toolResult: record.toolResult,
                          toolCallId: record.toolCallId)
    }
    
}
