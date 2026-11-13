import Foundation

/// A contiguous slice of a session's history plus its position in the WHOLE
/// session. A navigator jump can land in the middle of a chat, so the store
/// must know whether older AND newer rows remain instead of assuming the feed
/// is always the newest tail.
struct MessageWindow {
    let messages: [Message]
    /// 0-based position of `messages.first` in the session's total order.
    let startIndex: Int
    let totalCount: Int

    var endIndex: Int { startIndex + messages.count }
    var hasOlder: Bool { startIndex > 0 }
    var hasNewer: Bool { endIndex < totalCount }
}

extension DatabaseBridge {

    /// Session-wide navigator index: every user message, not just the loaded
    /// page. Built from a lightweight `substr` query so huge pastes are not
    /// materialised in memory.
    ///
    /// - Parameter sessionId: chat session id.
    /// - Returns: numbered entries in display order (empty on DB failure).
    func loadNavigatorIndex(sessionId: String) -> [UserMessageIndexEntry] {
        let records = (try? db.getUserMessageIndex(sessionId: sessionId)) ?? []
        return UserMessageIndexLogic.entries(from: records)
    }

    /// Number of visible user messages before a global message position.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - index: 0-based global position.
    /// - Returns: user-message count before that position.
    func userMessageCountBefore(sessionId: String, index: Int) -> Int {
        (try? db.countUserMessagesBefore(sessionId: sessionId, index: index)) ?? 0
    }

    /// Load a window centred on one message. Used when the navigator asks for
    /// a message that is not in the current feed: the app can jump straight to
    /// the first question of a 10k-message chat without paging through every
    /// intermediate page.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - messageID: target message id.
    ///   - before: rows to include above the target.
    ///   - after: rows to include below the target.
    /// - Returns: the window, or nil when the message does not exist.
    func loadMessageWindow(
        sessionId: String,
        messageID: String,
        before: Int,
        after: Int
    ) -> MessageWindow? {
        guard let position = try? db.messagePosition(
            sessionId: sessionId,
            messageID: messageID
        ) else { return nil }
        let total = (try? db.countMessages(sessionId: sessionId)) ?? 0
        guard total > 0 else { return nil }
        let start = max(0, position - max(0, before))
        let end = min(total, position + max(0, after) + 1)
        guard end > start else { return nil }
        let messages = loadMessages(
            sessionId: sessionId,
            limit: end - start,
            offset: start
        )
        guard !messages.isEmpty else { return nil }
        return MessageWindow(
            messages: messages,
            startIndex: start,
            totalCount: total
        )
    }

    /// One page immediately before a global position.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - beforeIndex: global position of the current first loaded row.
    ///   - pageSize: maximum rows to fetch.
    /// - Returns: page in display order plus whether even older rows remain.
    func loadOlderPage(
        sessionId: String,
        beforeIndex: Int,
        pageSize: Int
    ) -> (messages: [Message], hasMore: Bool) {
        let boundedBefore = max(0, beforeIndex)
        guard boundedBefore > 0, pageSize > 0 else { return ([], false) }
        let take = min(pageSize, boundedBefore)
        let offset = boundedBefore - take
        let page = loadMessages(sessionId: sessionId, limit: take, offset: offset)
        return (page, offset > 0)
    }

    /// One page immediately after a global position.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - afterIndex: global position one past the current last loaded row.
    ///   - pageSize: maximum rows to fetch.
    /// - Returns: page in display order plus whether even newer rows remain.
    func loadNewerPage(
        sessionId: String,
        afterIndex: Int,
        pageSize: Int
    ) -> (messages: [Message], hasMore: Bool) {
        let total = messageCount(sessionId: sessionId)
        let start = max(0, afterIndex)
        guard start < total, pageSize > 0 else { return ([], false) }
        let take = min(pageSize, total - start)
        let page = loadMessages(sessionId: sessionId, limit: take, offset: start)
        return (page, start + page.count < total)
    }
}
