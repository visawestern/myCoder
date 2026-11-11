import SwiftUI
import AppKit

extension ChatPanelView {
    func autoScrollIfPinned() {
        let messageCount = displayMessages.count
        let lastMessageID = displayMessages.last?.id
        let hasNewMessage = ChatScrollLogic.shouldScrollAfterNewMessage(
            oldCount: lastKnownMessageCount,
            newCount: messageCount,
            oldLastMessageID: lastKnownLastMessageID,
            newLastMessageID: lastMessageID
        )
        if lastKnownMessageCount != messageCount {
            lastKnownMessageCount = messageCount
        }
        if lastKnownLastMessageID != lastMessageID {
            lastKnownLastMessageID = lastMessageID
        }
        guard hasNewMessage || ChatScrollLogic.shouldAutoScroll(wasAtBottom: isChatBottomVisible) else { return }
        guard Date().timeIntervalSince(lastUserScrollAt) >= ChatScrollLogic.userScrollSuppression else { return }
        // The user is reading older content (recent wheel-up): never yank
        // them down while the answer is still growing below (user report
        // 2026-11-01: jumpy "chunk" scrolling during streaming).
        guard !ChatScrollLogic.shouldSuppressAutoScroll(
            lastWheelAt: lastUserScrollAt,
            lastWheelDirection: lastUserWheelDirection
        ) else { return }
        guard Date().timeIntervalSince(lastAutoScrollAt) >= ChatScrollLogic.minScrollInterval else { return }
        guard pendingAutoScrollTask == nil else { return }

        pendingAutoScrollTask = Task { @MainActor in
            defer { pendingAutoScrollTask = nil }
            try? await Task.sleep(nanoseconds: ChatScrollLogic.coalesceNanoseconds)
            guard !Task.isCancelled else { return }
            guard Date().timeIntervalSince(lastUserScrollAt) >= ChatScrollLogic.userScrollSuppression else { return }
            guard !ChatScrollLogic.shouldSuppressAutoScroll(
                lastWheelAt: lastUserScrollAt,
                lastWheelDirection: lastUserWheelDirection
            ) else { return }
            // Новое сообщение — жёсткий повод следовать за лентой (пользователь
            // только что отправил запрос). Стриминговые чанки следуют, только
            // если читатель уже внизу.
            if !hasNewMessage {
                guard isChatBottomVisible else { return }
            }
            lastAutoScrollAt = Date()
            followLatestContent()
        }
    }

    /// Applies the current latest-message anchor to the real AppKit scroll
    /// view. Input is measured view state; output is a clamped centered offset.
    /// Depends on ChatScrollBridge and the latest-row frame preference.
    func followLatestContent() {
        let snapshot = ChatScrollBridge.shared.currentSnapshot()
        guard snapshot.viewportHeight > 0, latestContentBottom > 0 else { return }
        let target = ChatScrollMath.followedOffset(
            latestContentBottom: latestContentBottom,
            viewportHeight: snapshot.viewportHeight,
            maxOffset: snapshot.maxOffsetY
        )
        ChatScrollBridge.shared.setOffset(target)
    }

    /// Позиция скролла приходит одним AppKit-наблюдателем. В состоянии
    /// обновляем только изменившиеся производные значения — иначе каждое
    /// колесо перестраивало бы весь чат (прежние GeometryReader-preferences
    /// делали именно это).
    func applyScrollSnapshot(_ snapshot: ChatScrollBridge.Snapshot,
                                     proxy: ScrollViewProxy) {
        guard snapshot.viewportHeight > 0 else { return }
        chatViewportHeight = snapshot.viewportHeight
        let wasAtBottom = isChatBottomVisible
        let heightChanged = ChatScrollMath.shouldReanchorFollowedContent(
            wasPinned: wasAtBottom,
            oldMaxOffset: lastKnownMaxOffset,
            newMaxOffset: snapshot.maxOffsetY
        )
        if abs(snapshot.maxOffsetY - lastKnownMaxOffset) > 1 {
            lastKnownMaxOffset = snapshot.maxOffsetY
        }
        if isChatBottomVisible != snapshot.isAtBottom {
            isChatBottomVisible = snapshot.isAtBottom
            messageStore.isPinnedToBottom = snapshot.isAtBottom
        }
        // Ленивая раскладка или замена streamed-текста тулзой изменили высоту:
        // в обоих направлениях пересчитываем позицию от последнего текста,
        // иначе после сокращения остаётся пустой хвост и резкий скачок.
        if heightChanged, wasAtBottom,
           !ChatScrollLogic.shouldSuppressAutoScroll(
               lastWheelAt: lastUserScrollAt,
               lastWheelDirection: lastUserWheelDirection
           ) {
            followLatestContent()
        }
        updateCurrentVisibleUserMessage(snapshot: snapshot)
        // Подгрузка начинается заранее, за экран до верха: к моменту, когда
        // читатель дойдёт до края, страница уже в памяти.
        if ChatPaginationLogic.shouldPrefetch(offsetY: snapshot.offsetY,
                                              viewportHeight: snapshot.viewportHeight),
           messageStore.hasMoreMessages,
           canLoadOlderMessages,
           !messageStore.isLoadingOlder,
           pendingPaginationAnchor == nil {
            loadOlderMessages(proxy: proxy)
        }
    }

    /// Кадры пользовательских строк в content-пространстве. Меняются только
    /// при изменении контента; здесь же компенсируется вставка страницы
    /// истории, чтобы вьюпорт не прыгал.
    func handleUserRowFrames(_ value: [String: CGRect]) {
        if value != userRowFrames {
            userRowFrames = value
        }
        if let latestID = displayMessages.last?.id, let frame = value[latestID] {
            latestContentBottom = frame.maxY
            if isChatBottomVisible, pendingPaginationAnchor == nil,
               !ChatScrollLogic.shouldSuppressAutoScroll(
                   lastWheelAt: lastUserScrollAt,
                   lastWheelDirection: lastUserWheelDirection
               ) {
                followLatestContent()
            }
        }
        if let pending = pendingPaginationAnchor,
           let newFrame = value[pending.messageID],
           abs(newFrame.minY - pending.oldMinY) > 0.5 {
            let snapshot = ChatScrollBridge.shared.currentSnapshot()
            let target = ChatPaginationLogic.preservedOffset(
                oldOffset: pending.oldOffset,
                anchorShift: newFrame.minY - pending.oldMinY,
                maxOffset: snapshot.maxOffsetY
            )
            ChatScrollBridge.shared.setOffset(target)
            pendingPaginationAnchor = nil
        }
        updateCurrentVisibleUserMessage()
    }

    /// Watches the user's wheel scrolling in this window. The timestamp is
    /// used to suppress auto-scroll for a beat after the user scrolls, so
    /// browsing older messages never gets yanked to the bottom.
    func installScrollWheelMonitor() {
        guard scrollEventMonitor == nil else { return }
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            ChatScrollBridge.shared.noteWheelEvent()
            if event.window != nil, NSApp.keyWindow === event.window {
                lastUserScrollAt = Date()
                lastUserWheelDirection = event.scrollingDeltaY >= 0 ? .up : .down
            }
            return event
        }
        ChatScrollBridge.shared.noteScrollMonitorInstalled()
    }

    func removeScrollWheelMonitor() {
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        scrollEventMonitor = nil
    }

    /// Keeps the visible message and the persisted draft in sync with the
    /// session the chat is now showing.
    func handleSessionChange(_ newID: String?, proxy: ScrollViewProxy) {
        guard ChatScrollLogic.shouldScrollOnSessionChange(
            oldSessionID: scrolledSessionID,
            newSessionID: newID
        ) else { return }
        scrolledSessionID = newID
        DispatchQueue.main.async {
            proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
        }
        settleAtBottom()
        loadDraft(for: newID)
    }

    /// Debounced draft persistence: typing must not write on every keystroke.
    func scheduleDraftSave(_ newText: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveDraft(newText)
            }
        }
    }

    func scrollToBottomOnAppear(proxy: ScrollViewProxy) {
        guard ChatScrollLogic.shouldScrollOnSessionChange(
            oldSessionID: scrolledSessionID,
            newSessionID: messageStore.currentSessionID
        ) else { return }
        scrolledSessionID = messageStore.currentSessionID
        DispatchQueue.main.async {
            proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
        }
        settleAtBottom()
    }

    /// После открытия чата ленивая раскладка досчитывает высоты строк уже
    /// ПОСЛЕ первого `scrollTo`, поэтому лента останавливается на десятки
    /// точек выше низа. Доводим позицию прямым offset'ом несколько раз, пока
    /// раскладка устояется, и только если пользователь ещё не читает вверх.
    func settleAtBottom() {
        for delay in [0.05, 0.15, 0.35, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard Date().timeIntervalSince(lastUserScrollAt) >= ChatScrollLogic.userScrollSuppression else {
                    return
                }
                ChatScrollBridge.shared.pinToBottom()
            }
        }
    }

    // MARK: - Notification focus (open the exact tool-call message)

    /// Applies a pending "show this message" request once its chat is loaded.
    /// The target may sit before the loaded tail; in that case older pages are
    /// fetched first instead of silently doing nothing.
    func applyPendingMessageFocus(proxy: ScrollViewProxy) {
        guard let request = appState.messageFocusRequest else { return }
        guard MessageFocusLogic.applies(request, to: messageStore.currentSessionID) else { return }
        guard !messageStore.isLoadingMessages else { return }

        if MessageFocusLogic.isLoaded(messageID: request.messageID, in: messageStore.messages) {
            revealFocusedMessage(request, proxy: proxy)
            return
        }
        guard messageStore.hasMoreMessages else {
            appState.clearMessageFocus(id: request.id)
            appState.shellActionNotice = "This tool call is no longer in the chat history."
            appState.shellActionNoticeTone = .error
            return
        }
        loadOlderPagesForFocus(request, proxy: proxy)
    }

    func revealFocusedMessage(_ request: MessageFocusRequest, proxy: ScrollViewProxy) {
        appState.clearMessageFocus(id: request.id)
        highlightedMessageID = request.messageID
        highlightClearTask?.cancel()
        highlightClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            if highlightedMessageID == request.messageID {
                highlightedMessageID = nil
            }
        }
        // LazyVStack needs a beat to lay the target row out; retry a few
        // times instead of scrolling once into an empty slot.
        for delay in [0.05, 0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard messageStore.currentSessionID == request.sessionID,
                      MessageFocusLogic.isLoaded(messageID: request.messageID, in: messageStore.messages) else {
                    return
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(request.messageID, anchor: .center)
                }
            }
        }
    }

    func loadOlderPagesForFocus(_ request: MessageFocusRequest, proxy: ScrollViewProxy) {
        guard focusLoadingTask == nil else { return }
        focusLoadingTask = Task { @MainActor in
            defer { focusLoadingTask = nil }
            guard let sessionID = messageStore.currentSessionID else { return }
            var attempts = 0
            while MessageFocusLogic.shouldLoadOlderPage(
                messageID: request.messageID,
                messages: messageStore.messages,
                hasMoreMessages: messageStore.hasMoreMessages,
                attempts: attempts
            ) {
                attempts += 1
                _ = await messageStore.loadHistory(sessionID: sessionID, client: appState.mimoClient)
                if !messageStore.hasMoreMessages {
                    // Local/auto-free chats have no server history; page the
                    // local store exactly like "Load earlier messages" does.
                    let loadedPage = messageStore.loadOlderFromDatabase(sessionId: sessionID)
                    if !loadedPage { break }
                }
                guard messageStore.currentSessionID == sessionID else { return }
            }
            guard MessageFocusLogic.applies(request, to: messageStore.currentSessionID),
                  MessageFocusLogic.isLoaded(messageID: request.messageID, in: messageStore.messages) else {
                appState.clearMessageFocus(id: request.id)
                appState.shellActionNotice = "This tool call is no longer in the chat history."
                appState.shellActionNoticeTone = .error
                return
            }
            revealFocusedMessage(request, proxy: proxy)
        }
    }

    func handleSelectedSessionChange(_ newSessionID: String?) {
        guard let sessionID = newSessionID else {
            // Detach, do not clear: a model turn started in another chat keeps
            // streaming into its own feed and must survive "no chat selected".
            messageStore.detach()
            messageText = ""
            attachmentStore.clear()
            stashedComposerDraft = nil
            restoreStashedDraftAfterSend = false
            composerHoldsQueuedMessage = false
            // M1: no chat selected → the composer shows the project default
            // routing and an empty journal, not the previous chat's state.
            reloadModelRouting()
            return
        }
        // M1: routing configuration and executed-route journal are per chat.
        reloadModelRouting()
        prepareMarkdownPrewarmProfile()
        if SessionReloadLogic.shouldReloadMessages(
            hasCachedMessages: messageStore.hasLoadedMessages(sessionID: sessionID)
        ) {
            loadSessionMessages(sessionID: sessionID)
        } else {
            // The chat is already in memory: show it immediately. Re-reading it
            // from the database would replace chunks of a turn that is still
            // streaming into this chat.
            messageStore.currentSessionID = sessionID
        }
        // User directive 2026-09-09: moving to another chat/project surfaces
        // THAT chat's pooled webview ("another tab of the same site") when one
        // exists; otherwise the panel keeps showing whatever it showed.
        let projectID = appState.selectedWorkspace?.id
            ?? appState.selectedWorkspace?.path ?? "global"
        appState.showPanelForChatIfPooled(projectID: projectID, chatID: sessionID)
    }

    /// Prewarming only pays off when it uses exactly the render profile of the
    /// visible rows (scaled font, theme, code settings). A fixed 14 pt / stale
    /// theme produced entries the renderer never asked for, so it looked like
    /// a cache but every row still rebuilt.
    func prepareMarkdownPrewarmProfile() {
        messageStore.markdownPrewarmProjectRoot = appState.toolWorkingDirectory
        messageStore.markdownPrewarmFontSize = InterfaceTypography.scaled(
            14,
            scale: appState.settings.zoom.fontScale
        )
        messageStore.markdownPrewarmTextColor = Color.mimo.textPrimary
        messageStore.markdownPrewarmCodeSettings = CodeDisplaySettings(settings: appState.settings)
        messageStore.markdownPrewarmIsLightInterface = Color.mimo.isLightTheme
    }

    func handleLoadedSessionChange(_ sessionID: String?) {
        if let sessionID {
            reattachPendingApprovals(sessionID: sessionID)
        }
        flushPendingSpecNodePrompt()
    }

    func handleViewAppear() {
        ChatPasteCoordinator.shared.register(store: attachmentStore) { text in
            if messageText.isEmpty {
                messageText = text
            } else {
                messageText += text
            }
        }
        messageQueue.setOnProcess { queued in
            Task {
                await self.sendDirectly(
                    text: queued.text,
                    files: queued.files,
                    images: queued.images,
                    agentModeOverride: queued.type.toAgentMode,
                    sessionID: queued.sessionID
                )
            }
        }
        if let sessionID = appState.selectedSession?.id {
            previousSessionID = sessionID
            prepareMarkdownPrewarmProfile()
            loadSessionMessages(sessionID: sessionID)
        }
        // M1: the panel can appear with a chat already selected (launch,
        // window reopen) — load that chat's routing config and journal.
        reloadModelRouting()
        // The model that is selected when the panel appears is the baseline
        // for the next switch: the notice names the model the chat came from.
        lastSelectedModel = appState.effectiveSelectedModel()
        flushPendingSpecNodePrompt()
        syncBackgroundActivity()
    }
}
