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
    ///
    /// A feed is normally the newest tail, but a navigator jump can replace it
    /// with a window in the middle of the chat. `windowStart` is the global
    /// position of `messages.first`; `hasMoreMessages` means older rows exist,
    /// `hasNewerMessages` means newer rows exist below the window.
    struct SessionFeed {
        var messages: [Message] = []
        var hasMoreMessages = true
        var hasNewerMessages = false
        var historyLimit = MessageHistoryPaginationLogic.initialLimit
        var olderUserMessageCount = 0
        /// 0-based position of `messages.first` in the whole session, when the
        /// feed came from the local database. `nil` for server-only feeds.
        var windowStart: Int?
        /// Every user message of the session, numbered 1…n. Built once per
        /// chat load and kept in memory, independent of the loaded page.
        var navigatorIndex: [UserMessageIndexEntry] = []
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

    var feeds: [String: SessionFeed] = [:]
    let maxVisible: Int
    let pruneBuffer: Int

    // Database integration
    var dbBridge: DatabaseBridge {
        DatabaseBridge.shared
    }

    /// Root used to resolve relative file paths while pre-rendering markdown
    /// in the background. Set by the chat panel (it knows the workspace).
    var markdownPrewarmProjectRoot: String? = nil

    /// Render profile used for prewarming. It must match the profile the chat
    /// rows actually pass to `SelectableMarkdownTextView` (scaled font, theme,
    /// code settings), otherwise every prewarmed entry is a cache miss.
    var markdownPrewarmFontSize: CGFloat = 14
    var markdownPrewarmTextColor: Color = Color.mimo.textPrimary
    var markdownPrewarmCodeSettings: CodeDisplaySettings = .default
    var markdownPrewarmIsLightInterface: Bool = Color.mimo.isLightTheme

    /// Only the newest prewarm pass matters (each one covers the whole visible
    /// feed); cancelling the previous task avoids piling up work on refreshes.
    private var markdownPrewarmTask: Task<Void, Never>?

    /// Стриминговые обновления пишутся в БД через троттлер, а не на каждый
    /// чанк (подробности — в `StreamingMessageWriter`). Инъекция нужна тестам.
    var streamingWriter: StreamingMessageWriter!

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

    init(maxVisible: Int = 100,
         pruneBuffer: Int = 30,
         streamingWriter: StreamingMessageWriter? = nil) {
        self.maxVisible = maxVisible
        self.pruneBuffer = pruneBuffer
        self.streamingWriter = streamingWriter ?? StreamingMessageWriter { [weak self] message, sessionID in
            self?.dbBridge.saveMessage(message, sessionId: sessionID)
        }
    }

    // MARK: - Visible feed accessors

    var visibleKey: String {
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

    /// Every user message of the visible chat, numbered 1…n. Unlike
    /// `messages`, this list does not shrink when only one history page is
    /// loaded — the navigator can show and jump to the whole session.
    var navigatorIndex: [UserMessageIndexEntry] {
        feeds[visibleKey]?.navigatorIndex ?? []
    }

    /// True when the loaded window is not the newest tail. The chat must then
    /// page DOWN as well as up (after a navigator jump to old history).
    var hasNewerMessages: Bool {
        feeds[visibleKey]?.hasNewerMessages ?? false
    }

    /// Global position of the first loaded message, when known.
    var windowStart: Int? {
        feeds[visibleKey]?.windowStart
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
        // Keep the session-wide navigator list in sync without re-querying the
        // database on every streamed chunk.
        if message.role == .user {
            feed.navigatorIndex = UserMessageIndexLogic.appending(
                message,
                to: feed.navigatorIndex
            )
        }
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
            // Раньше здесь был прямой saveMessage на каждый чанк ответа —
            // десятки тяжёлых SQLite-транзакций в секунду и дёрганье чата.
            streamingWriter.note(message, sessionID: key)
        }
        refreshStreamingSessions()
    }

    /// Reattaches in-memory approval cards after a session switch. Pending
    /// approvals live in `ToolApprovalCenter`, not the database, so a history
    /// reload must merge them back into the matching assistant message.
    /// Remove a message from the feed AND from the database.
    ///
    /// Used to roll back a compaction: the summary is only an appended
    /// message, so removing it restores the full model-bound history. The
    /// original turns were never dropped from the feed — only from the
    /// model's view — which is what makes the rollback exact.
    @discardableResult
    func remove(id: String) -> Bool {
        guard let key = feeds.first(where: { $0.value.messages.contains { $0.id == id } })?.key,
              let index = feeds[key]?.messages.firstIndex(where: { $0.id == id }) else { return false }
        objectWillChange.send()
        // Read-modify-write through a local feed: evaluating the RHS while a
        // mutating subscript access to `feeds` is open is an exclusivity
        // violation (and crashed the test runner).
        if var feed = feeds[key] {
            feed.messages.remove(at: index)
            feed.navigatorIndex = UserMessageIndexLogic.removing(
                id: id,
                from: feed.navigatorIndex
            )
            feeds[key] = feed
        }
        // Не даём отложенной записи воскресить удалённое сообщение.
        streamingWriter.cancel(id: id)
        if !key.isEmpty {
            dbBridge.deleteMessage(id: id)
        }
        refreshStreamingSessions()
        return true
    }

    func setPendingApprovals(_ approvalsByAssistant: [String: [PendingToolApproval]]) {
        guard !messages.isEmpty else { return }
        objectWillChange.send()
        // Mutate a local copy: assigning into `feeds[...]` while the RHS reads
        // the same dictionary is an exclusivity violation.
        guard var feed = feeds[visibleKey] else { return }
        for index in feed.messages.indices {
            feed.messages[index].pendingApprovals =
                approvalsByAssistant[feed.messages[index].id] ?? []
        }
        feeds[visibleKey] = feed
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
        streamingWriter.flushAll()
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
        streamingWriter.flushAll()
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

    func prune(_ key: String) {
        guard var feed = feeds[key] else { return }
        guard feed.messages.count > maxVisible + pruneBuffer else { return }
        if key == visibleKey && !isPinnedToBottom { return }

        let dropCount = feed.messages.count - maxVisible
        let dropped = feed.messages.prefix(dropCount)
        if let start = feed.windowStart {
            // A windowed feed remembers its global position, so dropping rows
            // from the top just moves the window forward.
            feed.windowStart = start + dropCount
        }
        feed.olderUserMessageCount += UserMessageNavigatorLogic.userMessageCount(Array(dropped))
        feed.messages.removeFirst(dropCount)
        // Dropped history stays reachable through "Load earlier messages".
        feed.hasMoreMessages = true
        feeds[key] = feed
    }

    func refreshStreamingSessions() {
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

    // MARK: - Markdown pre-rendering

    /// Pre-build the attributed markdown for large messages in the background
    /// right after history loads. The first scroll into a big message then
    /// finds a ready layout instead of stalling the main thread (user report
    /// 2026-11-01: thumb spins at the message boundary).
    ///
    /// The chat splits a message at fenced code blocks and inline images and
    /// gives only the prose segments to the selectable markdown renderer;
    /// code blocks and images have their own views. Prewarming the raw message
    /// text would therefore build entries no row ever asks for, so the same
    /// split is applied here.
    func scheduleMarkdownPrewarm(for messages: [Message]? = nil) {
        let source = messages ?? self.messages
        let proseTexts = MarkdownMediaSegmentLogic.proseTexts(
            from: source.filter { !$0.isStreaming }.map(\.content)
        )

        markdownPrewarmTask?.cancel()
        markdownPrewarmTask = nil
        guard !proseTexts.isEmpty else { return }

        let fontSize = markdownPrewarmFontSize
        let textColor = markdownPrewarmTextColor
        let root = markdownPrewarmProjectRoot
        let settings = markdownPrewarmCodeSettings
        let isLight = markdownPrewarmIsLightInterface
        markdownPrewarmTask = Task.detached(priority: .utility) {
            MarkdownAttributedStringBuilder.prewarm(
                texts: proseTexts,
                fontSize: fontSize,
                textColor: textColor,
                projectRoot: root,
                codeSettings: settings,
                isLightInterface: isLight
            )
        }
    }

}
