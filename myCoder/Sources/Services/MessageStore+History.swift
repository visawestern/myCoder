import Foundation

/// History loading, bidirectional paging and the session-wide navigator
/// index. Split out of `MessageStore.swift` to keep every file under the
/// 600-line limit and to make history logic independently testable.
extension MessageStore {
    // MARK: - History

    /// Загрузить сообщения сессии из локальной БД (вместо API).
    /// Грузит ХВОСТ (новейшие `limit`) — oldest-first прятал бы все новые
    /// сообщения, как только сессия перерастает страницу.
    @MainActor
    func loadFromDatabase(sessionId: String, limit: Int? = nil) {
        // История читается из БД — сначала сбросим отложенные записи, иначе
        // БД может оказаться старше уже показанного в памяти ответа.
        streamingWriter.flushAll()
        self.currentSessionID = sessionId
        let loadedMessages = dbBridge.loadMessageTail(sessionId: sessionId, take: limit)

        objectWillChange.send()
        var feed = feeds[sessionId] ?? SessionFeed()
        if feed.messages.isEmpty {
            feed.messages = loadedMessages
        } else {
            // Refresh of a chat that already has a live feed: keep newer
            // in-memory rows (a running stream can be ahead of the database)
            // and only fill in messages this feed does not know yet.
            var indexByID = Dictionary(
                uniqueKeysWithValues: feed.messages.enumerated().map { ($1.id, $0) }
            )
            for message in loadedMessages {
                if let index = indexByID[message.id] {
                    if !feed.messages[index].isStreaming {
                        feed.messages[index] = message
                    }
                } else {
                    feed.messages.append(message)
                    indexByID[message.id] = feed.messages.count - 1
                }
            }
        }

        let totalCount = dbBridge.messageCount(sessionId: sessionId)
        let start = max(0, totalCount - feed.messages.count)
        feed.windowStart = start
        feed.hasMoreMessages = start > 0
        feed.hasNewerMessages = false
        feed.olderUserMessageCount = dbBridge.userMessageCountBefore(
            sessionId: sessionId,
            index: start
        )
        // Build the session-wide navigator list once per chat load. The DB
        // query reads only a short prefix of each user message.
        let storedIndex = dbBridge.loadNavigatorIndex(sessionId: sessionId)
        feed.navigatorIndex = UserMessageIndexLogic.merging(
            messages: feed.messages,
            into: storedIndex
        )
        feeds[sessionId] = feed
        refreshStreamingSessions()
        scheduleMarkdownPrewarm(for: loadedMessages)
    }

    /// Догрузить одну страницу более старых сообщений из локальной БД
    /// (для сессий без серверной истории: local/auto-free). Дубликаты по id
    /// пропускаются — хвост мог сдвинуться живыми дописываниями.
    @MainActor
    @discardableResult
    func loadOlderFromDatabase(sessionId: String, pageSize: Int = 20) -> Bool {
        var feed = feeds[sessionId] ?? SessionFeed()
        // A middle window has a real global start. A tail feed without one
        // computes it from the total count, preserving the old behaviour.
        let start = feed.windowStart
            ?? max(0, dbBridge.messageCount(sessionId: sessionId) - feed.messages.count)
        let page = dbBridge.loadOlderPage(
            sessionId: sessionId,
            beforeIndex: start,
            pageSize: pageSize
        )
        let existingIDs = Set(feed.messages.map(\.id))
        let fresh = page.messages.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else {
            feed.windowStart = start
            feed.hasMoreMessages = page.hasMore
            feeds[sessionId] = feed
            objectWillChange.send()
            return false
        }
        objectWillChange.send()
        feed.messages = fresh + feed.messages
        feed.windowStart = max(0, start - fresh.count)
        feed.hasMoreMessages = page.hasMore
        feed.olderUserMessageCount = dbBridge.userMessageCountBefore(
            sessionId: sessionId,
            index: feed.windowStart ?? 0
        )
        feeds[sessionId] = feed
        return true
    }

    static func message(from serverMsg: MimoMessageResponse) -> Message {
        let role: MessageRole = serverMsg.info?.role == "user" ? .user : .assistant
        var content = ""
        var reasoningText = ""
        var parts: [MessagePartContent] = []
        var attachedImages: [ClipboardImage] = []

        if let responseParts = serverMsg.parts {
            for part in responseParts {
                switch part {
                case .text(let t):
                    content = t
                    parts.append(.text(t))
                case .reasoning(let r):
                    reasoningText = r
                    parts.append(.reasoning(r))
                case .stepStart:
                    parts.append(.stepStart)
                case .stepFinish:
                    parts.append(.stepFinish)
                case .toolInvocation(let name, let input, let result, let callID):
                    parts.append(.toolCall(name: name, args: input ?? "{}", result: result, callID: callID))
                case .image(let mediaType, let data):
                    parts.append(.image(base64: data, mimeType: mediaType))
                    if role == .user, !data.isEmpty {
                        attachedImages.append(ClipboardImage(base64: data, mimeType: mediaType))
                    }
                case .other:
                    break
                }
            }
        }

        if content.isEmpty {
            content = serverMsg.textContent
        }

        return Message(
            id: serverMsg.info?.id ?? UUID().uuidString,
            role: role,
            content: content,
            parts: parts,
            reasoning: reasoningText,
            isFinished: true,
            attachedImages: attachedImages.isEmpty ? nil : attachedImages
        )
    }

    @MainActor
    @discardableResult
    func mergeOlderMessages(from serverMessages: [MimoMessageResponse]) -> Bool {
        let loadedMessages = serverMessages.map { Self.message(from: $0) }
        let existingIDs = Set(messages.map(\.id))
        let newMessages = loadedMessages.filter { !existingIDs.contains($0.id) }
        let allServerIDs = Set(loadedMessages.map(\.id))

        guard !newMessages.isEmpty else {
            hasMoreMessages = false
            return false
        }

        objectWillChange.send()
        var feed = feeds[visibleKey] ?? SessionFeed()
        if let start = feed.windowStart {
            feed.windowStart = max(0, start - newMessages.count)
            feed.olderUserMessageCount = dbBridge.userMessageCountBefore(
                sessionId: visibleKey,
                index: feed.windowStart ?? 0
            )
        }
        feed.messages = newMessages + feed.messages
        feed.navigatorIndex = UserMessageIndexLogic.merging(
            messages: feed.messages,
            into: feed.navigatorIndex
        )
        feeds[visibleKey] = feed

        let localIDs = Set(messages.map(\.id))
        if allServerIDs.isSubset(of: localIDs) {
            hasMoreMessages = false
        }
        scheduleMarkdownPrewarm(for: newMessages)
        return true
    }

    /// Incremental refresh: keeps existing messages untouched, updates changed
    /// ones in place and appends only the genuinely new tail. Never clears the
    /// feed, so unchanged rows are not re-created (no screen flicker).
    @MainActor
    @discardableResult
    func mergeLatestMessages(from serverMessages: [MimoMessageResponse]) -> Int {
        let incoming = serverMessages.map { Self.message(from: $0) }
        var appendedCount = 0

        objectWillChange.send()
        var feed = feeds[visibleKey] ?? SessionFeed()
        for message in incoming {
            if let index = feed.messages.firstIndex(where: { $0.id == message.id }) {
                if Self.hasDisplayChanges(existing: feed.messages[index], incoming: message) {
                    feed.messages[index] = message
                }
            } else {
                feed.messages.append(message)
                appendedCount += 1
            }
        }
        // A server tail refresh means the feed is pinned to the newest rows
        // again; any previous middle-window state is no longer valid.
        let totalCount = dbBridge.messageCount(sessionId: visibleKey)
        feed.windowStart = totalCount > 0
            ? max(0, totalCount - feed.messages.count)
            : nil
        feed.hasNewerMessages = false
        feed.navigatorIndex = UserMessageIndexLogic.merging(
            messages: feed.messages,
            into: dbBridge.loadNavigatorIndex(sessionId: visibleKey)
        )
        feeds[visibleKey] = feed

        pruneIfNeeded()
        scheduleMarkdownPrewarm(for: incoming)
        return appendedCount
    }

    static func hasDisplayChanges(existing: Message, incoming: Message) -> Bool {
        existing.content != incoming.content
            || existing.reasoning != incoming.reasoning
            || existing.parts.count != incoming.parts.count
    }

    @MainActor
    func loadHistory(sessionID: String, client: MimoServeClient) async -> Bool {
        guard !isLoadingOlder, hasMoreMessages else { return false }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let requestedLimit = MessageHistoryPaginationLogic.nextLimit(after: currentHistoryLimit)
            let serverMessages = try await client.getMessages(
                sessionID: sessionID,
                limit: requestedLimit
            )
            guard !serverMessages.isEmpty else {
                hasMoreMessages = false
                return false
            }
            let loadedNewMessages = mergeOlderMessages(from: serverMessages)
            currentHistoryLimit = requestedLimit
            hasMoreMessages = loadedNewMessages
                && MessageHistoryPaginationLogic.hasMore(
                    receivedCount: serverMessages.count,
                    requestedLimit: requestedLimit
                )
            return loadedNewMessages
        } catch {
            hasMoreMessages = false
            return false
        }
    }

    // MARK: - Navigator jump and bidirectional paging

    /// Rebuild the in-memory navigator index from the database and the rows
    /// currently in memory. Called after a history load; never on every
    /// streamed chunk (live appends update the index incrementally).
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - extra: freshly loaded rows that may not be persisted yet.
    @MainActor
    func refreshNavigatorIndex(sessionId: String, using extra: [Message] = []) {
        guard var feed = feeds[sessionId] else { return }
        let merged = UserMessageIndexLogic.merging(
            messages: feed.messages + extra,
            into: dbBridge.loadNavigatorIndex(sessionId: sessionId)
        )
        guard merged != feed.navigatorIndex else { return }
        objectWillChange.send()
        feed.navigatorIndex = merged
        feeds[sessionId] = feed
    }

    /// Replace the visible feed with a window around one message.
    ///
    /// This is what makes "click the first question of a 10k-message chat"
    /// instant: the database returns the target window directly instead of the
    /// app paging through hundreds of intermediate pages.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - messageID: target message id.
    ///   - context: rows kept above and below the target.
    /// - Returns: true when the message is now in the feed.
    @MainActor
    @discardableResult
    func jumpToMessage(
        sessionId: String,
        messageID: String,
        context: Int = 12
    ) -> Bool {
        guard currentSessionID == sessionId else { return false }
        if feeds[sessionId]?.messages.contains(where: { $0.id == messageID }) == true {
            return true
        }
        guard let window = dbBridge.loadMessageWindow(
            sessionId: sessionId,
            messageID: messageID,
            before: context,
            after: context
        ) else { return false }

        objectWillChange.send()
        var feed = feeds[sessionId] ?? SessionFeed()
        feed.messages = window.messages
        feed.windowStart = window.startIndex
        feed.hasMoreMessages = window.hasOlder
        feed.hasNewerMessages = window.hasNewer
        feed.olderUserMessageCount = dbBridge.userMessageCountBefore(
            sessionId: sessionId,
            index: window.startIndex
        )
        if feed.navigatorIndex.isEmpty {
            feed.navigatorIndex = dbBridge.loadNavigatorIndex(sessionId: sessionId)
        }
        feed.navigatorIndex = UserMessageIndexLogic.merging(
            messages: window.messages,
            into: feed.navigatorIndex
        )
        feeds[sessionId] = feed
        scheduleMarkdownPrewarm(for: window.messages)
        refreshStreamingSessions()
        return true
    }

    /// Append one page immediately below a middle window. Without this the
    /// chat would dead-end after a jump to old history.
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - pageSize: maximum rows to append.
    /// - Returns: true when at least one newer message was appended.
    @MainActor
    @discardableResult
    func loadNewerFromDatabase(sessionId: String, pageSize: Int = 20) -> Bool {
        guard var feed = feeds[sessionId], feed.hasNewerMessages else { return false }
        let afterIndex = (feed.windowStart ?? 0) + feed.messages.count
        let page = dbBridge.loadNewerPage(
            sessionId: sessionId,
            afterIndex: afterIndex,
            pageSize: pageSize
        )
        let existingIDs = Set(feed.messages.map(\.id))
        let fresh = page.messages.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else {
            feed.hasNewerMessages = false
            feeds[sessionId] = feed
            objectWillChange.send()
            return false
        }
        objectWillChange.send()
        feed.messages.append(contentsOf: fresh)
        feed.hasNewerMessages = page.hasMore
        feeds[sessionId] = feed
        scheduleMarkdownPrewarm(for: fresh)
        return true
    }

    /// Replace a middle window with the newest tail again (the scroll-to-
    /// bottom button after a jump).
    ///
    /// - Parameters:
    ///   - sessionId: chat session id.
    ///   - limit: tail size; nil loads the whole history.
    @MainActor
    func resetToTail(sessionId: String, limit: Int? = nil) {
        streamingWriter.flushAll()
        guard currentSessionID == sessionId else { return }
        objectWillChange.send()
        var feed = feeds[sessionId] ?? SessionFeed()
        feed.messages = dbBridge.loadMessageTail(sessionId: sessionId, take: limit)
        let totalCount = dbBridge.messageCount(sessionId: sessionId)
        let start = max(0, totalCount - feed.messages.count)
        feed.windowStart = start
        feed.hasMoreMessages = start > 0
        feed.hasNewerMessages = false
        feed.olderUserMessageCount = dbBridge.userMessageCountBefore(
            sessionId: sessionId,
            index: start
        )
        if feed.navigatorIndex.isEmpty {
            feed.navigatorIndex = dbBridge.loadNavigatorIndex(sessionId: sessionId)
        }
        feed.navigatorIndex = UserMessageIndexLogic.merging(
            messages: feed.messages,
            into: feed.navigatorIndex
        )
        feeds[sessionId] = feed
        scheduleMarkdownPrewarm(for: feed.messages)
        refreshStreamingSessions()
    }
}
