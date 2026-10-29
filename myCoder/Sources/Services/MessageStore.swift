import Foundation
import SwiftUI

/// Message feed of one chat panel.
///
/// The store keeps **one feed per session** instead of a single array. That is
/// what makes a background model turn possible: the turn keeps writing into
/// its own chat's feed while the user reads another chat, and switching back
/// shows everything that streamed meanwhile. Writes are routed by message id,
/// so a chunk that arrives after the user switched chats still lands in the
/// conversation it belongs to — and is saved to that conversation's database.
class MessageStore: ObservableObject {
    /// Loaded state of one conversation.
    private struct SessionFeed {
        var messages: [Message] = []
        var hasMoreMessages = true
        var historyLimit = MessageHistoryPaginationLogic.initialLimit
        var olderUserMessageCount = 0
    }

    /// Session currently shown by the panel. Changing it swaps the visible
    /// feed and leaves every other feed untouched.
    @Published var currentSessionID: String? {
        didSet {
            if oldValue != currentSessionID {
                objectWillChange.send()
            }
        }
    }

    @Published var isLoadingOlder = false
    /// Session whose history load is in flight. A dedicated ID (instead of a
    /// plain Bool) prevents a slow, superseded load from clearing the loader
    /// of the session the user switched to afterwards.
    @Published var loadingSessionID: String?
    /// Session whose history is fully applied. A one-shot prompt for a new
    /// spec-node chat waits for this instead of racing the async load.
    @Published var loadedSessionID: String?
    /// Sessions with a message that is still streaming. The sidebar reads this
    /// to show an activity indicator for chats the user is not looking at.
    @Published private(set) var streamingSessionIDs: Set<String> = []

    var isLoadingMessages: Bool {
        loadingSessionID != nil
    }

    private var feeds: [String: SessionFeed] = [:]
    private let maxVisible: Int
    private let pruneBuffer: Int

    // Database integration
    private var dbBridge: DatabaseBridge {
        DatabaseBridge.shared
    }

    /// Kept in sync with the chat's bottom anchor. While the user reads old
    /// history, pruning is deferred so rows never disappear under the cursor;
    /// the deferred prune runs as soon as the feed is pinned to the bottom again.
    var isPinnedToBottom = true {
        didSet {
            if isPinnedToBottom && !oldValue {
                pruneIfNeeded()
            }
        }
    }

    init(maxVisible: Int = 100, pruneBuffer: Int = 30) {
        self.maxVisible = maxVisible
        self.pruneBuffer = pruneBuffer
    }

    // MARK: - Visible feed accessors

    private var visibleKey: String {
        currentSessionID ?? ""
    }

    /// Messages of the chat the panel is showing.
    var messages: [Message] {
        feeds[visibleKey]?.messages ?? []
    }

    var hasMoreMessages: Bool {
        get { feeds[visibleKey]?.hasMoreMessages ?? true }
        set {
            objectWillChange.send()
            var feed = feeds[visibleKey] ?? SessionFeed()
            feed.hasMoreMessages = newValue
            feeds[visibleKey] = feed
        }
    }

    var currentHistoryLimit: Int {
        get { feeds[visibleKey]?.historyLimit ?? MessageHistoryPaginationLogic.initialLimit }
        set {
            objectWillChange.send()
            var feed = feeds[visibleKey] ?? SessionFeed()
            feed.historyLimit = newValue
            feeds[visibleKey] = feed
        }
    }

    /// User messages that live before the loaded window. The chat navigator
    /// adds this offset so its numbering spans the whole session instead of
    /// only the page that happens to be loaded.
    var olderUserMessageCount: Int {
        feeds[visibleKey]?.olderUserMessageCount ?? 0
    }

    // MARK: - Cross-session access

    /// Messages of any loaded session, whether or not it is on screen.
    func messages(in sessionID: String?) -> [Message] {
        feeds[sessionID ?? ""]?.messages ?? []
    }

    /// One message by id across every loaded session. A running turn must use
    /// this instead of the visible feed: the user may have switched chats.
    func message(id: String) -> Message? {
        for feed in feeds.values {
            if let message = feed.messages.first(where: { $0.id == id }) {
                return message
            }
        }
        return nil
    }

    /// Session that owns a message. Streaming callbacks identify their turn by
    /// message id and must resolve the chat from it, because the visible feed
    /// may be a different conversation.
    func sessionID(owningMessageID: String) -> String? {
        feeds.first(where: { $0.value.messages.contains { $0.id == owningMessageID } })?.key
    }

    /// Whether the session already has a loaded feed (cached, not necessarily
    /// shown). Selecting such a chat must not re-read and replace its history:
    /// a background stream may be ahead of the last database write.
    func hasLoadedMessages(sessionID: String) -> Bool {
        !(feeds[sessionID]?.messages.isEmpty ?? true)
    }

    // MARK: - Mutation

    func append(_ message: Message) {
        append(message, to: currentSessionID)
    }

    /// Append to a specific session. Streaming routes capture their session
    /// before the first await and always write there.
    func append(_ message: Message, to sessionID: String?) {
        let key = sessionID ?? ""
        objectWillChange.send()
        var feed = feeds[key] ?? SessionFeed()
        feed.messages.append(message)
        feeds[key] = feed
        prune(key)

        if key.isEmpty {
            MyCoderAPIServer.appendLog("❌ MessageStore.append: currentSessionID is nil, message \(message.id) not saved")
        } else {
            MyCoderAPIServer.appendLog("📝 MessageStore.append: saving message \(message.id) to session \(key)")
            dbBridge.saveMessage(message, sessionId: key)
        }
        refreshStreamingSessions()
    }

    func update(id: String, mutate: (inout Message) -> Void) {
        guard let key = feeds.first(where: { $0.value.messages.contains { $0.id == id } })?.key,
              let index = feeds[key]?.messages.firstIndex(where: { $0.id == id }) else { return }

        objectWillChange.send()
        mutate(&feeds[key]!.messages[index])
        let message = feeds[key]!.messages[index]
        if !key.isEmpty {
            dbBridge.saveMessage(message, sessionId: key)
        }
        refreshStreamingSessions()
    }

    /// Reattaches in-memory approval cards after a session switch. Pending
    /// approvals live in `ToolApprovalCenter`, not the database, so a history
    /// reload must merge them back into the matching assistant message.
    func setPendingApprovals(_ approvalsByAssistant: [String: [PendingToolApproval]]) {
        guard !messages.isEmpty else { return }
        objectWillChange.send()
        for index in feeds[visibleKey]!.messages.indices {
            feeds[visibleKey]!.messages[index].pendingApprovals =
                approvalsByAssistant[feeds[visibleKey]!.messages[index].id] ?? []
        }
    }

    func setFinished(id: String) {
        update(id: id) { msg in
            msg.isFinished = true
            msg.isStreaming = false
        }
    }

    /// Drop every loaded conversation. Used by tests and by a full reset; the
    /// panel itself calls `detach()` when no chat is selected so background
    /// turns keep their feeds.
    func clear() {
        objectWillChange.send()
        feeds.removeAll()
        currentSessionID = nil
        loadingSessionID = nil
        loadedSessionID = nil
        streamingSessionIDs = []
    }

    /// Stop showing a chat without discarding any feed. A turn that is still
    /// streaming into one of those feeds keeps running.
    func detach() {
        currentSessionID = nil
        loadingSessionID = nil
        loadedSessionID = nil
    }

    // MARK: - Pruning

    /// Hysteresis pruning: the feed may grow `pruneBuffer` messages past
    /// `maxVisible` before old rows are dropped in one batch. This keeps
    /// appends cheap (no row shifts on every message) and only trims when the
    /// user is pinned to the bottom, where removed rows are far off-screen.
    /// Background feeds are never on screen, so they can always be trimmed.
    func pruneIfNeeded() {
        prune(visibleKey)
    }

    private func prune(_ key: String) {
        guard var feed = feeds[key] else { return }
        guard feed.messages.count > maxVisible + pruneBuffer else { return }
        if key == visibleKey && !isPinnedToBottom { return }

        let dropped = feed.messages.prefix(feed.messages.count - maxVisible)
        feed.olderUserMessageCount += UserMessageNavigatorLogic.userMessageCount(Array(dropped))
        feed.messages.removeFirst(feed.messages.count - maxVisible)
        // Dropped history stays reachable through "Load earlier messages".
        feed.hasMoreMessages = true
        feeds[key] = feed
    }

    private func refreshStreamingSessions() {
        var ids: Set<String> = []
        for (key, feed) in feeds where !key.isEmpty {
            if feed.messages.contains(where: { $0.isStreaming }) {
                ids.insert(key)
            }
        }
        if ids != streamingSessionIDs {
            streamingSessionIDs = ids
        }
    }

    // MARK: - History

    /// Загрузить сообщения сессии из локальной БД (вместо API).
    /// Грузит ХВОСТ (новейшие `limit`) — oldest-first прятал бы все новые
    /// сообщения, как только сессия перерастает страницу.
    @MainActor
    func loadFromDatabase(sessionId: String, limit: Int? = nil) {
        self.currentSessionID = sessionId
        // Heal conversations whose newest part was written to the global store
        // while the session's project route was unknown — those rows are moved
        // into the project database before the tail is read, so the tail
        // includes them.
        dbBridge.recoverGlobalMessages(sessionId: sessionId)
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

        if !feed.messages.isEmpty {
            feed.hasMoreMessages = dbBridge.messageCount(sessionId: sessionId) > feed.messages.count
        } else {
            feed.hasMoreMessages = false
        }
        feed.olderUserMessageCount = max(
            0,
            dbBridge.userMessageCount(sessionId: sessionId) - UserMessageNavigatorLogic.userMessageCount(feed.messages)
        )
        feeds[sessionId] = feed
        refreshStreamingSessions()
    }

    /// Догрузить одну страницу более старых сообщений из локальной БД
    /// (для сессий без серверной истории: local/auto-free). Дубликаты по id
    /// пропускаются — хвост мог сдвинуться живыми дописываниями.
    @MainActor
    @discardableResult
    func loadOlderFromDatabase(sessionId: String, pageSize: Int = 20) -> Bool {
        var feed = feeds[sessionId] ?? SessionFeed()
        let page = dbBridge.loadOlderPage(
            sessionId: sessionId,
            loadedCount: feed.messages.count,
            pageSize: pageSize
        )
        let existingIDs = Set(feed.messages.map(\.id))
        let fresh = page.messages.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else {
            feed.hasMoreMessages = page.hasMore
            feeds[sessionId] = feed
            objectWillChange.send()
            return false
        }
        objectWillChange.send()
        feed.messages = fresh + feed.messages
        feed.hasMoreMessages = page.hasMore
        feed.olderUserMessageCount = max(
            0,
            feed.olderUserMessageCount - UserMessageNavigatorLogic.userMessageCount(fresh)
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
        feed.messages = newMessages + feed.messages
        feeds[visibleKey] = feed

        let localIDs = Set(messages.map(\.id))
        if allServerIDs.isSubset(of: localIDs) {
            hasMoreMessages = false
        }
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
        feeds[visibleKey] = feed

        pruneIfNeeded()
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
}
