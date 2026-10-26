import Foundation
import SwiftUI

class MessageStore: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoadingOlder = false
    @Published var hasMoreMessages = true
    /// Session whose history load is in flight. A dedicated ID (instead of a
    /// plain Bool) prevents a slow, superseded load from clearing the loader
    /// of the session the user switched to afterwards.
    @Published var loadingSessionID: String?
    /// Session whose history is fully applied. A one-shot prompt for a new
    /// spec-node chat waits for this instead of racing the async load.
    @Published var loadedSessionID: String?

    var isLoadingMessages: Bool {
        loadingSessionID != nil
    }
    
    private let maxVisible: Int
    private let pruneBuffer: Int
    var currentSessionID: String?
    var currentHistoryLimit = MessageHistoryPaginationLogic.initialLimit
    /// User messages that live before the loaded window. The chat navigator
    /// adds this offset so its numbering spans the whole session instead of
    /// only the page that happens to be loaded.
    @Published var olderUserMessageCount = 0
    
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
    
    func append(_ message: Message) {
        messages.append(message)
        pruneIfNeeded()
        
        // Auto-save to database
        if let sessionId = currentSessionID {
            MyCoderAPIServer.appendLog("📝 MessageStore.append: saving message \(message.id) to session \(sessionId)")
            dbBridge.saveMessage(message, sessionId: sessionId)
        } else {
            MyCoderAPIServer.appendLog("❌ MessageStore.append: currentSessionID is nil, message \(message.id) not saved")
        }
    }
    
    func update(id: String, mutate: (inout Message) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[idx])
        
        // Auto-save updated message to database
        if let sessionId = currentSessionID {
            dbBridge.saveMessage(messages[idx], sessionId: sessionId)
        }
    }
    
    /// Reattaches in-memory approval cards after a session switch. Pending
    /// approvals live in `ToolApprovalCenter`, not the database, so a history
    /// reload must merge them back into the matching assistant message.
    func setPendingApprovals(_ approvalsByAssistant: [String: [PendingToolApproval]]) {
        for index in messages.indices {
            messages[index].pendingApprovals = approvalsByAssistant[messages[index].id] ?? []
        }
    }

    func setFinished(id: String) {
        update(id: id) { msg in
            msg.isFinished = true
            msg.isStreaming = false
        }
    }
    
    func clear() {
        messages = []
        hasMoreMessages = true
        loadingSessionID = nil
        loadedSessionID = nil
        currentSessionID = nil
        currentHistoryLimit = MessageHistoryPaginationLogic.initialLimit
        olderUserMessageCount = 0
    }

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

        if !loadedMessages.isEmpty {
            self.messages = loadedMessages
            self.hasMoreMessages = dbBridge.messageCount(sessionId: sessionId) > loadedMessages.count
        } else {
            self.messages = []
            self.hasMoreMessages = false
        }
        self.olderUserMessageCount = max(
            0,
            dbBridge.userMessageCount(sessionId: sessionId) - UserMessageNavigatorLogic.userMessageCount(loadedMessages)
        )
    }

    /// Догрузить одну страницу более старых сообщений из локальной БД
    /// (для сессий без серверной истории: local/auto-free). Дубликаты по id
    /// пропускаются — хвост мог сдвинуться живыми дописываниями.
    @MainActor
    @discardableResult
    func loadOlderFromDatabase(sessionId: String, pageSize: Int = 20) -> Bool {
        let page = dbBridge.loadOlderPage(sessionId: sessionId, loadedCount: messages.count, pageSize: pageSize)
        let existingIDs = Set(messages.map(\.id))
        let fresh = page.messages.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else {
            hasMoreMessages = page.hasMore
            return false
        }
        messages = fresh + messages
        hasMoreMessages = page.hasMore
        olderUserMessageCount = max(
            0,
            olderUserMessageCount - UserMessageNavigatorLogic.userMessageCount(fresh)
        )
        return true
    }
    
    /// Hysteresis pruning: the feed may grow `pruneBuffer` messages past
    /// `maxVisible` before old rows are dropped in one batch. This keeps
    /// appends cheap (no row shifts on every message) and only trims when the
    /// user is pinned to the bottom, where removed rows are far off-screen.
    func pruneIfNeeded() {
        guard isPinnedToBottom else { return }
        guard messages.count > maxVisible + pruneBuffer else { return }
        let dropped = messages.prefix(messages.count - maxVisible)
        olderUserMessageCount += UserMessageNavigatorLogic.userMessageCount(Array(dropped))
        messages.removeFirst(messages.count - maxVisible)
        // Dropped history stays reachable through "Load earlier messages".
        hasMoreMessages = true
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

        messages = newMessages + messages
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

        for message in incoming {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                if Self.hasDisplayChanges(existing: messages[index], incoming: message) {
                    messages[index] = message
                }
            } else {
                messages.append(message)
                appendedCount += 1
            }
        }

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
