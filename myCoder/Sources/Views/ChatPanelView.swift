import SwiftUI
import AppKit

private func localToolParts(
    _ parts: [MessagePartContent],
    settingResult result: String,
    callID: String
) -> [MessagePartContent] {
    parts.map { part in
        guard case .toolCall(let name, let args, _, let id) = part, id == callID else {
            return part
        }
        return .toolCall(name: name, args: args, result: result, callID: id)
    }
}

/// Composer contents saved while a queued message is being edited. Restored
/// after that edited message is sent so the user's in-progress draft is not lost.
private struct ComposerDraftSnapshot {
    let text: String
    let files: [FileInfo]
    let images: [ClipboardImage]

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && files.isEmpty
            && images.isEmpty
    }
}

private struct PreparedLocalToolCall {
    let call: WebToolCall
    let callID: String
    let validationError: WebToolValidationError?
    let approval: PendingToolApproval?
    /// Set in plan mode for mutating tools: the call is refused without a
    /// user prompt, and this reason is reported back to the model.
    let denialReason: String?

    var argsSummary: String {
        call.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}

struct ChatPanelView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var messageStore = MessageStore()
    @StateObject private var messageQueue = MessageQueue()
    @StateObject private var attachmentStore = MessageAttachmentStore()
    @State private var messageText = ""
    @State private var stashedComposerDraft: ComposerDraftSnapshot?
    @State private var restoreStashedDraftAfterSend = false
    @State private var composerHoldsQueuedMessage = false
    @State private var showFilePicker = false
    @State private var streamingText = ""
    @State private var currentAssistantMessageID: String?
    @State private var currentTask: Task<Void, Never>?
    @State private var previousSessionID: String?
    @State private var isChatBottomVisible = true
    @State private var userRowFrames: [String: CGRect] = [:]
    @State private var chatViewportFrame: CGRect = .zero
    /// Last measured frame of the bottom sentinel (used to decide whether a
    /// scroll is actually needed).
    @State private var lastBottomFrame: CGRect = .zero
    /// Timestamp of the user's last wheel scroll: auto-scroll is suppressed
    /// right after, so reading older messages is never yanked back.
    @State private var lastUserScrollAt = Date.distantPast
    /// Direction of the user's last wheel gesture. While it is `.up`, the
    /// auto-scroll is suppressed for `upwardReadingProtection` so a growing
    /// answer below never yanks the reader out of older content (user report
    /// 2026-11-01: «прокрутка стопорится / прокручивает сразу куском»).
    @State private var lastUserWheelDirection: ChatScrollLogic.WheelDirection?
    /// Timestamp of the last auto-scroll (throttle).
    @State private var lastAutoScrollAt = Date.distantPast
    /// One scheduled auto-scroll at a time (coalescing).
    @State private var pendingAutoScrollTask: Task<Void, Never>?
    /// Message count / newest id of the last revision: growth of the count
    /// AND a new newest id means a new message was appended (not older
    /// messages prepended by history pagination).
    @State private var lastKnownMessageCount = 0
    @State private var lastKnownLastMessageID: String?
    @State private var scrollEventMonitor: Any?
    @State private var currentUserMessageID: String?
    @State private var canLoadOlderMessages = false
    @State private var scrolledSessionID: String?
    /// Message to outline after a notification tap jumps to it.
    @State private var highlightedMessageID: String?
    @State private var highlightClearTask: Task<Void, Never>?
    @State private var focusLoadingTask: Task<Void, Never>?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var serveTimeoutTask: Task<Void, Never>?
    @State private var isCompacting = false
    #if canImport(WebKit)
    @State private var activeWebProviderID: String?
    @State private var activeWebChatID: String?
    @State private var webCatalogRefreshKeys: Set<String> = []
    @State private var captchaSolverContext: WebCaptchaSolverContext?
    /// Approval mailbox of the CURRENT web-agent turn: the Allow/Deny card
    /// resolves the pending request through this box.
    @State private var activeApprovalBox: WebToolApprovalBox?
    /// Minimap vs half-chat panel (user directive 2026-09-09: minimap by
    /// default, expand on tap). Persisted so the choice survives restarts.
    @AppStorage("mycoder.webBrowserPanelExpanded") private var webBrowserPanelExpanded = false
    #endif
    private let sseClient = SSEClient()
    private let db = DatabaseManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            #if canImport(WebKit)
            // User directive 2026-09-09: for a web provider the live vendor
            // page is VISIBLE in the chat — a small minimap thumbnail by
            // default (bottom-trailing overlay, expands on tap), or the
            // half-chat panel when expanded. Both re-parent the same pooled
            // WKWebView, so the page — login, conversation, in-flight
            // stream — survives across requests; switching chats moves the
            // panel to that chat's webview ("another tab of the same site").
            // Non-web providers leave the panel as is.
            if webBrowserPanelExpanded,
               let panelConfig = appState.webBrowserPanelConfig,
               let webConfig = WebProviderStore.load().first(where: { $0.id == panelConfig.providerID }) {
                WebProviderBrowserPanel(
                    config: panelConfig,
                    isExpanded: true,
                    onExpand: { webBrowserPanelExpanded = true },
                    onCollapseToMini: { webBrowserPanelExpanded = false },
                    onHide: { appState.hideWebBrowserPanel() }
                ) { size in
                    let tabKey = AntiBrowserTabManager.makeKey(providerID: webConfig.id,
                                                              projectID: panelConfig.projectID,
                                                              chatID: panelConfig.chatID)
                    let bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
                    CastPanelHost(bridge: bridge)
                        .frame(width: size.width, height: size.height)
                }
            }
            #endif

            if ChatPanelLayoutLogic.shouldUseCenteredInput(messageCount: messageStore.messages.count) {
                centeredInputState
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if ChatLoadingIndicatorLogic.presentation(
                                    isLoading: messageStore.isLoadingMessages,
                                    messageCount: messageStore.messages.count
                                ) == .inline {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        ProgressView().scaleEffect(0.8)
                                        Text(L.t(AppLocalizationKey.locLoadingMessages))
                                            .interfaceFont(size: 12)
                                            .foregroundColor(Color.mimo.textMuted)
                                        Spacer()
                                    }.padding(.vertical, 8)
                                } else if messageStore.isLoadingOlder {
                                    HStack {
                                        Spacer()
                                        ProgressView().scaleEffect(0.8)
                                        Text(L.t(AppLocalizationKey.locLoadingOlderMessages))
                                            .interfaceFont(size: 12)
                                            .foregroundColor(Color.mimo.textMuted)
                                        Spacer()
                                    }.padding(.vertical, 8)
                                } else if messageStore.hasMoreMessages {
                                    Button(L.t(AppLocalizationKey.locLoadingOlderMessages)) {
                                        loadOlderMessages(proxy: proxy)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .interfaceFont(size: 12, weight: .medium)
                                    .foregroundColor(Color.mimo.cyan)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .onAppear {
                                        guard canLoadOlderMessages else { return }
                                        loadOlderMessages(proxy: proxy)
                                    }
                                }
                                
                                ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
                                    if let separator = workedSeparator(before: index, in: displayMessages) {
                                        WorkedTimeSeparator(label: separator)
                                    }
                                    
                                    MessageRow(
                                        message: message,
                                        projectRoot: appState.toolWorkingDirectory,
                                        isHighlighted: message.id == highlightedMessageID
                                    )
                                        .id(message.id)
                                        .chatRowFrameReporter(id: message.id, isUser: message.role == .user)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(ChatScrollLogic.bottomAnchorID)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ChatBottomFrameKey.self,
                                                value: geo.frame(in: .named(ChatScrollSpace.name))
                                            )
                                        }
                                    )

                                // Second attachment point for the scroll bridge:
                                // this one lives INSIDE the lazy content near
                                // the bottom sentinel, so it is materialized
                                // whenever the chat is pinned to the bottom
                                // (where the auto-scroll and wheel behavior are
                                // reproduced). The outer .background probe is
                                // the always-present fallback.
                                ChatScrollProbe()
                                    .frame(width: 0, height: 0)
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 16 + ChatScrollLogic.bottomContentInset)
                        }
                        .chatScrollSpaceReporter()
                        .background(
                            // Live scroll diagnostics: the probe climbs to the
                            // enclosing NSScrollView and registers it with the
                            // bridge for /api/scroll. It lives OUTSIDE the
                            // LazyVStack so it exists even when the lazy stack
                            // has no visible rows.
                            ChatScrollProbe()
                                .frame(width: 0, height: 0)
                        )
                        .onPreferenceChange(ChatRowFrameKey.self) { value in
                            userRowFrames = value
                        }
                        .onPreferenceChange(ChatViewportFrameKey.self) { value in
                            chatViewportFrame = value
                        }
                        .onPreferenceChange(ChatBottomFrameKey.self) { value in
                            updateChatBottomVisibility(bottomFrame: value)
                        }
                        .onChange(of: userRowFrames) { _ in updateCurrentVisibleUserMessage() }
                        .onChange(of: chatViewportFrame) { _ in updateCurrentVisibleUserMessage() }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            updateCurrentVisibleUserMessage()
                        }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            autoScrollIfPinned(proxy: proxy)
                        }
                        .onChange(of: messageStore.currentSessionID) { newID in
                            handleSessionChange(newID, proxy: proxy)
                        }
                        .onChange(of: appState.messageFocusRequest?.token) { _ in
                            applyPendingMessageFocus(proxy: proxy)
                        }
                        .onChange(of: messageStore.loadedSessionID) { _ in
                            applyPendingMessageFocus(proxy: proxy)
                        }
                        .onChange(of: messageText) { newText in
                            scheduleDraftSave(newText)
                        }
                        .onAppear {
                            installScrollWheelMonitor()
                            scrollToBottomOnAppear(proxy: proxy)
                            applyPendingMessageFocus(proxy: proxy)
                            ChatScrollBridge.shared.registerAnchorJumper { id, anchor in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: anchor)
                                }
                            }
                        }
                        .onDisappear {
                            pendingAutoScrollTask?.cancel()
                            removeScrollWheelMonitor()
                            ChatScrollBridge.shared.clearAnchorJumper()
                            ChatScrollBridge.shared.detach()
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if ChatScrollLogic.showsScrollToBottomButton(
                                isBottomVisible: isChatBottomVisible,
                                messageCount: displayMessages.count
                            ) {
                                ScrollToBottomButton {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
                                    }
                                }
                                .padding(.trailing, 16)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                .animation(.easeOut(duration: 0.15), value: isChatBottomVisible)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            UserMessageNavigator(
                                messages: displayMessages,
                                currentMessageID: currentUserMessageID,
                                offset: messageStore.olderUserMessageCount
                            ) { messageID in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(messageID, anchor: .top)
                                }
                            }
                            .padding(.trailing, 12)
                        }
                    }

                    ComposerAttachmentPreview(store: attachmentStore)

                    if let pending = appState.pendingQuestionRequest,
                       pending.sessionID == messageStore.currentSessionID {
                        PlanQuestionCardView(questions: pending.questions) { answers in
                            submitQuestionAnswers(answers)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    BottomInputBar(
                        messageText: $messageText,
                        onSend: sendMessage,
                        onStop: stopGeneration,
                        isLoading: visibleSessionIsStreaming,
                        attachmentStore: attachmentStore,
                        showFilePicker: $showFilePicker,
                        messageQueue: messageQueue,
                        contextUsage: currentContextUsage,
                        isCompilingContext: appState.isCompilingContext,
                        contextPreparationStage: appState.contextPreparationStage,
                        isLoadingMessages: messageStore.isLoadingMessages,
                        onForceSendQueued: forceSendQueued,
                        onEditQueued: editQueuedMessage
                    )
                }
            }
        }
        .background(Color.mimo.background)
        #if canImport(WebKit)
        .overlay(alignment: .bottomTrailing) {
            // Minimap mode: small live thumbnail floating at the chat's
            // bottom-trailing corner (user directive 2026-09-09). Tapping
            // expands to the half-chat panel; the pooled webview stays
            // alive in both modes.
            if !webBrowserPanelExpanded,
               let panelConfig = appState.webBrowserPanelConfig,
               let webConfig = WebProviderStore.load().first(where: { $0.id == panelConfig.providerID }) {
                WebProviderBrowserPanel(
                    config: panelConfig,
                    isExpanded: false,
                    onExpand: { webBrowserPanelExpanded = true },
                    onCollapseToMini: { webBrowserPanelExpanded = false },
                    onHide: { appState.hideWebBrowserPanel() }
                ) { size in
                    let tabKey = AntiBrowserTabManager.makeKey(providerID: webConfig.id,
                                                              projectID: panelConfig.projectID,
                                                              chatID: panelConfig.chatID)
                    let bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
                    CastPanelHost(bridge: bridge)
                        .frame(width: size.width, height: size.height)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 64)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(item: $captchaSolverContext) { context in
            WebCaptchaSolverView(context: context)
        }
        #endif
        .onChange(of: appState.selectedSession?.id) { newSessionID in
            handleSelectedSessionChange(newSessionID)
        }
        .onChange(of: appState.isLoading) { loading in
            if !loading {
                messageQueue.processNext()
                flushPendingSpecNodePrompt()
            }
        }
        .onChange(of: messageStore.streamingSessionIDs) { _ in
            syncBackgroundActivity()
        }
        .onChange(of: appState.pendingQuestionRequest) { _ in
            syncBackgroundActivity()
        }
        .onChange(of: appState.pendingSpecNodePrompt?.id) { _ in
            flushPendingSpecNodePrompt()
        }
        .onChange(of: messageStore.loadedSessionID) { sessionID in
            handleLoadedSessionChange(sessionID)
        }
        .onChange(of: messageStore.loadingSessionID) { newID in
            appState.loadingChatSessionID = newID
            flushPendingSpecNodePrompt()
        }
        .onAppear {
            handleViewAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editMessage)) { notification in
            editMessageFromNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resendMessage)) { notification in
            resendMessageFromNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .retryMessage)) { notification in
            guard let messageID = notification.userInfo?["messageId"] as? String else { return }
            retryAssistantMessage(messageID: messageID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopGeneration)) { _ in
            stopGeneration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiSendRequested)) { notification in
            handleAPISendRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .submitPlanQuestionAnswers)) { notification in
            guard let answers = notification.userInfo?["answers"] as? [[String]] else { return }
            submitQuestionAnswers(answers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localToolApprovalResolved)) { notification in
            handleLocalToolApprovalResolved(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .webToolApprovalResolved)) { notification in
            handleWebToolApprovalResolved(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyEntireChat)) { _ in
            copyEntireChat()
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleImportedFiles(result)
        }
    }

    /// Imports the files chosen in the file picker.
    ///
    /// Kept out of the view body on purpose: the body expression is large
    /// enough that the Swift type-checker times out ("unable to type-check
    /// this expression in reasonable time") when this closure is inlined.
    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let name = url.lastPathComponent
            let ext = url.pathExtension
            let type = FileType.from(ext: ext)
            let path = url.path
            attachmentStore.appendFile(FileInfo(name: name, type: type, path: path))
        }
    }

    /// Empty-chat state with the centered composer.
    ///
    /// Kept as a separate view property so `body` stays within the Swift
    /// type-checker's budget.
    @ViewBuilder
    private var centeredInputState: some View {
        let presentation = ChatLoadingIndicatorLogic.presentation(
            isLoading: messageStore.isLoadingMessages,
            messageCount: messageStore.messages.count
        )
        EmptyChatStateView(
            messageText: $messageText,
            attachmentStore: attachmentStore,
            showFilePicker: $showFilePicker,
            messageQueue: messageQueue,
            onSend: sendMessage,
            onStop: stopGeneration,
            isLoading: visibleSessionIsStreaming,
            isLoadingChat: presentation == .centered,
            onForceSendQueued: forceSendQueued,
            onEditQueued: editQueuedMessage
        )
    }

    /// The send path must not depend on the user opening the @ picker first.
    /// It uses the already-built index only: the baseline is built once in the
    /// background when a workspace opens, and FSEvents keep it fresh via
    /// `ProjectFileIndexEventUpdater` — the send path never scans.
    private static func recordsForPointContext(projectPath: String) async -> [FileIndexRecord] {
        guard !projectPath.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            ProjectFileIndexStore.load(projectPath: projectPath)
        }.value
    }

    /// One bounded local planning pass (R9). The model sees only the top-K
    /// entities and answers with a JSON plan; a missing local model, an empty
    /// candidate set, a timeout or a rejected answer all become a visible
    /// fallback that the deterministic plan then replaces.

    /// `/remember <text>`: store the fact in the project database and confirm
    /// it in chat. A write failure is reported, never swallowed.
    @MainActor
    private func rememberProjectFact(_ text: String) async {
        let projectPath = appState.selectedWorkspace?.path ?? ""
        guard !projectPath.isEmpty else {
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryFailed),
                isFinished: true
            ))
            return
        }
        guard let chunk = ProjectMemoryExtraction.chunk(text: text, projectPath: projectPath) else {
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryUsage),
                isFinished: true
            ))
            return
        }

        let saved: Result<Void, Error> = await Task.detached(priority: .utility) {
            do {
                let store = try ProjectDatabaseManager.manager(forProjectPath: projectPath).makeMemoryStore()
                try store.upsert(chunk)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch saved {
        case .success:
            messageStore.append(Message(
                role: .assistant,
                content: "\(L.t(AppLocalizationKey.locMemorySaved)): \(chunk.text)",
                isFinished: true
            ))
        case .failure:
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryFailed),
                isFinished: true
            ))
        }
    }

    // MARK: - Body event handlers
    //
    // These live outside `body` on purpose: the view body is large enough that
    // inlining the closures makes the Swift type-checker time out
    // ("unable to type-check this expression in reasonable time").

    /// Auto-scrolls to the newest message unless the reader scrolled away.
    ///
    /// No animation: the revision changes on every streamed token, and a
    /// restarting animated `scrollTo` fights the user's own scrolling.
    /// The scroll is throttled and coalesced:
    /// - at most one scroll per `minScrollInterval` (a burst of tokens → one
    ///   scroll per chunk, not one per token);
    /// - suppressed for `userScrollSuppression` after the user's wheel scroll,
    ///   so reading older messages is never yanked back while the pin state
    ///   (measured from layout preferences) is still catching up;
    /// - skipped entirely when the bottom anchor is already glued to the
    ///   viewport bottom (no drift → nothing to do).
    private func autoScrollIfPinned(proxy: ScrollViewProxy) {
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
            if !hasNewMessage {
                guard isChatBottomVisible else { return }
                if ChatScrollLogic.anchorIsGlued(bottomFrame: lastBottomFrame, viewport: chatViewportFrame) {
                    return
                }
            }
            lastAutoScrollAt = Date()
            proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
        }
    }

    private func updateChatBottomVisibility(bottomFrame: CGRect) {
        lastBottomFrame = bottomFrame
        guard let visible = ChatScrollLogic.bottomVisibility(
            bottomFrame: bottomFrame,
            viewport: chatViewportFrame
        ) else { return }
        isChatBottomVisible = visible
        messageStore.isPinnedToBottom = visible
    }

    /// Watches the user's wheel scrolling in this window. The timestamp is
    /// used to suppress auto-scroll for a beat after the user scrolls, so
    /// browsing older messages never gets yanked to the bottom.
    private func installScrollWheelMonitor() {
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

    private func removeScrollWheelMonitor() {
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        scrollEventMonitor = nil
    }

    /// Keeps the visible message and the persisted draft in sync with the
    /// session the chat is now showing.
    private func handleSessionChange(_ newID: String?, proxy: ScrollViewProxy) {
        guard ChatScrollLogic.shouldScrollOnSessionChange(
            oldSessionID: scrolledSessionID,
            newSessionID: newID
        ) else { return }
        scrolledSessionID = newID
        DispatchQueue.main.async {
            proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
        }
        loadDraft(for: newID)
    }

    /// Debounced draft persistence: typing must not write on every keystroke.
    private func scheduleDraftSave(_ newText: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveDraft(newText)
            }
        }
    }

    private func scrollToBottomOnAppear(proxy: ScrollViewProxy) {
        guard ChatScrollLogic.shouldScrollOnSessionChange(
            oldSessionID: scrolledSessionID,
            newSessionID: messageStore.currentSessionID
        ) else { return }
        scrolledSessionID = messageStore.currentSessionID
        DispatchQueue.main.async {
            proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
        }
    }

    // MARK: - Notification focus (open the exact tool-call message)

    /// Applies a pending "show this message" request once its chat is loaded.
    /// The target may sit before the loaded tail; in that case older pages are
    /// fetched first instead of silently doing nothing.
    private func applyPendingMessageFocus(proxy: ScrollViewProxy) {
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

    private func revealFocusedMessage(_ request: MessageFocusRequest, proxy: ScrollViewProxy) {
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

    private func loadOlderPagesForFocus(_ request: MessageFocusRequest, proxy: ScrollViewProxy) {
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

    private func handleSelectedSessionChange(_ newSessionID: String?) {
        guard let sessionID = newSessionID else {
            // Detach, do not clear: a model turn started in another chat keeps
            // streaming into its own feed and must survive "no chat selected".
            messageStore.detach()
            messageText = ""
            attachmentStore.clear()
            stashedComposerDraft = nil
            restoreStashedDraftAfterSend = false
            composerHoldsQueuedMessage = false
            return
        }
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
        #if canImport(WebKit)
        // User directive 2026-09-09: moving to another chat/project surfaces
        // THAT chat's pooled webview ("another tab of the same site") when one
        // exists; otherwise the panel keeps showing whatever it showed.
        let projectID = appState.selectedWorkspace?.id
            ?? appState.selectedWorkspace?.path ?? "global"
        appState.showPanelForChatIfPooled(projectID: projectID, chatID: sessionID)
        #endif
    }

    /// Prewarming only pays off when it uses exactly the render profile of the
    /// visible rows (scaled font, theme, code settings). A fixed 14 pt / stale
    /// theme produced entries the renderer never asked for, so it looked like
    /// a cache but every row still rebuilt.
    private func prepareMarkdownPrewarmProfile() {
        messageStore.markdownPrewarmProjectRoot = appState.toolWorkingDirectory
        messageStore.markdownPrewarmFontSize = InterfaceTypography.scaled(
            14,
            scale: appState.settings.zoom.fontScale
        )
        messageStore.markdownPrewarmTextColor = Color.mimo.textPrimary
        messageStore.markdownPrewarmCodeSettings = CodeDisplaySettings(settings: appState.settings)
        messageStore.markdownPrewarmIsLightInterface = Color.mimo.isLightTheme
    }

    private func handleLoadedSessionChange(_ sessionID: String?) {
        if let sessionID {
            reattachPendingApprovals(sessionID: sessionID)
        }
        flushPendingSpecNodePrompt()
    }

    private func handleViewAppear() {
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
        flushPendingSpecNodePrompt()
        syncBackgroundActivity()
    }

    /// Mirror the panel's live turns into `AppState`, where the sidebar reads
    /// them. A chat waiting for a plan answer counts as active: the model is
    /// paused but the turn is not over.
    @MainActor
    private func syncBackgroundActivity() {
        var ids = messageStore.streamingSessionIDs
        if let pending = appState.pendingQuestionRequest {
            ids.insert(pending.sessionID)
        }
        if ids != appState.streamingSessionIDs {
            appState.streamingSessionIDs = ids
        }
    }

    /// Whether the chat currently on screen has a live turn. The composer
    /// shows Stop only for that chat; a background turn is stopped from its
    /// own row/chat, not from an unrelated composer.
    private var visibleSessionIsStreaming: Bool {
        guard let sessionID = messageStore.currentSessionID else { return false }
        return appState.streamingSessionIDs.contains(sessionID)
    }

    private func editMessageFromNotification(_ notification: Notification) {
        guard let messageID = notification.userInfo?["messageId"] as? String,
              let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
        loadMessageIntoComposer(message)
    }

    private func resendMessageFromNotification(_ notification: Notification) {
        guard let messageID = notification.userInfo?["messageId"] as? String,
              let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
        resendMessage(message)
    }

    private func handleAPISendRequest(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? String, !message.isEmpty else { return }
        if let chatId = notification.userInfo?["chatId"] as? String, !chatId.isEmpty {
            messageStore.currentSessionID = chatId
        }
        messageText = message
        sendMessage()
    }

    private func handleLocalToolApprovalResolved(_ notification: Notification) {
        guard let approvalID = notification.userInfo?["approvalID"] as? String,
              let approved = notification.userInfo?["approved"] as? Bool else { return }
        Task { @MainActor in
            let assistantID = ToolApprovalCenter.shared.assistantID(for: approvalID)
            ToolApprovalCenter.shared.resolve(id: approvalID, approved: approved)
            appState.notificationService.remove(approvalID)
            if let assistantID {
                messageStore.update(id: assistantID) { msg in
                    msg.pendingApprovals.removeAll { $0.id == approvalID }
                }
            }
            MyCoderAPIServer.appendLog(
                "⏸ local tool approval tapped: id=\(approvalID) approved=\(approved)"
            )
        }
    }

    private func handleWebToolApprovalResolved(_ notification: Notification) {
        guard let approvalID = notification.userInfo?["approvalID"] as? String,
              let approved = notification.userInfo?["approved"] as? Bool else { return }
        activeApprovalBox?.resolve(id: approvalID, approved: approved)
        // Clear the card from the assistant message: the driver resumes with
        // the verdict and the turn continues.
        if let idx = messageStore.messages.firstIndex(where: {
            $0.pendingApprovalID == approvalID
        }) {
            messageStore.update(id: messageStore.messages[idx].id) { m in
                m.pendingApprovalID = nil
                m.pendingApprovalTool = nil
                m.pendingApprovalMessage = nil
            }
        }
    }

    private func copyEntireChat() {
        switch ChatCopyLogic.result(from: messageStore.messages) {
        case .empty:
            NotificationCenter.default.post(name: .copyEntireChatUnavailable, object: nil)
        case .copied(let transcript):
            NSPasteboard.general.clearContents()
            let didCopy = NSPasteboard.general.setString(transcript, forType: .string)
            NotificationCenter.default.post(
                name: didCopy ? .copyEntireChatCompleted : .copyEntireChatUnavailable,
                object: nil
            )
        }
    }
    
    private var displayMessages: [Message] {
        MessageDisplayLogic.messagesForDisplay(messageStore.messages)
    }
    
    private func workedSeparator(before index: Int, in messages: [Message]) -> String? {
        guard index > 0 else { return nil }
        let previous = messages[index - 1]
        let current = messages[index]
        let gap = current.timestamp.timeIntervalSince(previous.timestamp)
        guard gap >= 5 else { return nil }
        return SessionSendLogic.workedDurationLabel(since: previous.timestamp, until: current.timestamp)
    }
    
    /// Sends a queued spec-node prompt exactly once, after the target chat has
    /// loaded and no other request is in flight.
    @MainActor
    private func flushPendingSpecNodePrompt() {
        guard let pending = appState.pendingSpecNodePrompt else { return }
        if SpecNodePromptFlushLogic.needsHistoryLoad(
            pendingSessionID: pending.sessionID,
            selectedSessionID: appState.selectedSession?.id,
            loadedSessionID: messageStore.loadedSessionID,
            isLoadingMessages: messageStore.isLoadingMessages
        ) {
            loadSessionMessages(sessionID: pending.sessionID)
            return
        }
        guard SpecNodePromptFlushLogic.shouldFlush(
            pendingSessionID: pending.sessionID,
            selectedSessionID: appState.selectedSession?.id,
            currentSessionID: messageStore.currentSessionID,
            loadedSessionID: messageStore.loadedSessionID,
            isLoadingMessages: messageStore.isLoadingMessages,
            isBusy: appState.isLoading
        ) else { return }
        appState.pendingSpecNodePrompt = nil
        messageText = pending.text
        sendMessage()
    }

    func loadSessionMessages(sessionID: String) {
        canLoadOlderMessages = false
        // Clear only on a real session switch; refreshing the same session
        // merges incrementally so unchanged rows don't blink.
        let isSameSessionRefresh = messageStore.currentSessionID == sessionID
            && !messageStore.messages.isEmpty
        if !isSameSessionRefresh {
            // Detach the visible feed instead of wiping it: other chats may be
            // mid-stream and their feeds must stay intact.
            messageStore.detach()
            messageStore.currentSessionID = sessionID
        }
        messageStore.loadingSessionID = sessionID

        Task {
            defer {
                Task { @MainActor in
                    if messageStore.loadingSessionID == sessionID {
                        messageStore.loadingSessionID = nil
                    }
                }
            }
            appState.scheduleGitRefresh(sessionID: sessionID)
            let initialLimit = MessageHistoryPaginationLogic.initialLimit
            var messages: [MimoMessageResponse] = []
            var hasMoreMessages = false
            // When the server has nothing (or is unreachable) we fall back to the
            // local database. That path deals in local `Message` values, not the
            // server `MimoMessageResponse` DTO — the app no longer shells out to
            // the mimo CLI — so we flag it and load straight into the store.
            var useLocalFallback = false
            do {
                // Standalone/local-only chats were never on the server: asking
                // it first hangs the load on a slow/routing-broken connection
                // (default URLSession timeout is 60s) and the chat looks
                // empty for a minute. A disconnected server fails fast, but a
                // half-open one does not — probe cheaply and go straight to
                // the local DB when the server is known-down.
                if appState.serverConnected {
                    let serverMessages = try await appState.mimoClient.getMessages(
                        sessionID: sessionID,
                        limit: initialLimit
                    )
                    if serverMessages.isEmpty {
                        useLocalFallback = true
                    } else {
                        messages = serverMessages
                        hasMoreMessages = MessageHistoryPaginationLogic.hasMore(
                            receivedCount: serverMessages.count,
                            requestedLimit: initialLimit
                        )
                    }
                } else {
                    useLocalFallback = true
                }
            } catch {
                useLocalFallback = true
            }
            let loadedMessages = messages
            let canLoadMore = hasMoreMessages
            let fallbackToLocal = useLocalFallback
            await MainActor.run {
                guard messageStore.currentSessionID == sessionID else { return }

                if fallbackToLocal {
                    // Load the session's history from the local DB directly as
                    // `Message` values (this also sets hasMoreMessages); no
                    // server-DTO merge, no CLI.
                    messageStore.loadFromDatabase(sessionId: sessionID, limit: initialLimit)
                } else {
                    appState.applySessionPlan(from: loadedMessages)
                    if let selections = SessionSendLogic.restoreSelections(from: loadedMessages) {
                        appState.applySendSelections(selections)
                    }
                    messageStore.mergeLatestMessages(from: loadedMessages)
                    messageStore.hasMoreMessages = canLoadMore
                }

                if !isSameSessionRefresh {
                    messageStore.currentHistoryLimit = initialLimit
                }
                // Attach still-pending approval cards to the messages that
                // were just loaded. Doing it here (not only in the
                // loadedSessionID observer) keeps the cards alive when the
                // history is reloaded while a turn waits for a verdict.
                reattachPendingApprovals(sessionID: sessionID)
                // Clear the loader before publishing the loaded marker: a
                // pending spec-node prompt is flushed from both onChange
                // hooks, and leaving the loader set here made the loaded
                // callback see isLoadingMessages == true and drop the send.
                messageStore.loadingSessionID = nil
                messageStore.loadedSessionID = sessionID
                flushPendingSpecNodePrompt()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard messageStore.currentSessionID == sessionID else { return }
                    canLoadOlderMessages = true
                }
            }
        }
    }
    
    @MainActor
    private func recordRejectedSend(text: String,
                                    files: [FileInfo],
                                    images: [ClipboardImage],
                                    error: String,
                                    existingUserMessageID: String? = nil) {
        let preparedSessionID: String?
        if messageStore.currentSessionID == nil {
            preparedSessionID = appState.prepareLocalSessionForSend(title: text)
            messageStore.currentSessionID = preparedSessionID
        } else {
            preparedSessionID = messageStore.currentSessionID
        }
        // Force-send already appended the user bubble; never append a second
        // copy just because the send was rejected.
        if existingUserMessageID == nil {
            let userMessage = Message(
                role: .user,
                content: text,
                files: files.isEmpty ? nil : files,
                parts: MessagePartsBuilder.displayParts(text: text, images: images)
            )
            messageStore.append(userMessage)
        }
        messageStore.append(Message(role: .assistant, content: error, isFinished: true))
        if let preparedSessionID,
           let preparedSession = appState.sessions.first(where: { $0.id == preparedSessionID }) {
            appState.selectedSession = preparedSession
        }
    }

    @MainActor
    private func prepareSessionBeforeAppending(
        route: SendRoute,
        title: String,
        sessionID: String?
    ) async -> String? {
        // The send targets the session captured when it was requested, not
        // whatever chat happens to be visible after the preparation awaits.
        if let sessionID {
            return sessionID
        }

        if case .mimoServe = route {
            do {
                let remote = try await appState.mimoClient.createSession(title: String(title.prefix(50)))
                if let workspace = appState.selectedWorkspace {
                    DatabaseBridge.shared.createSession(
                        id: remote.id,
                        projectId: workspace.path,
                        title: remote.title,
                        directory: workspace.path,
                        branch: workspace.branch,
                        agentMode: appState.agentMode.rawValue,
                        modelId: appState.selectedModel.isEmpty ? nil : appState.selectedModel,
                        providerId: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID
                    )
                } else {
                    // Audit 2026-09-09: a serve-route chat started with NO
                    // workspace got no DB row at all (only the `if let
                    // workspace` branch persisted) — after restart it
                    // vanished from the sidebar even though its messages
                    // live in the global DB under the server session id.
                    // Persist it as standalone so it survives and shows in
                    // the Chats group like every other workspace-less chat.
                    DatabaseBridge.shared.createSession(
                        id: remote.id,
                        projectId: ChatSession.standaloneProjectKey,
                        title: remote.title,
                        directory: ChatSession.standaloneProjectKey,
                        branch: nil,
                        agentMode: appState.agentMode.rawValue,
                        modelId: appState.selectedModel.isEmpty ? nil : appState.selectedModel,
                        providerId: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID
                    )
                }
                appState.registerSessionFromServer(
                    id: remote.id,
                    title: remote.title,
                    directory: appState.selectedWorkspace?.path ?? remote.directory,
                    select: false
                )
                return remote.id
            } catch {
                return nil
            }
        }

        return appState.prepareLocalSessionForSend(title: title)
    }

    func sendMessage() {
        guard MessageSendValidation.canSend(
            text: messageText,
            images: attachmentStore.attachedImages,
            files: attachmentStore.attachedFiles
        ) else { return }

        // Slash command interception (plan Раздел 5 Блок 3 п.30). Commands that
        // don't map to plain text are handled locally and short-circuit the send;
        // instruction-injecting commands rewrite the outgoing text.
        if messageText.hasPrefix("/") {
            let executor = SlashCommandExecutor(hasGitRepo: !(appState.selectedWorkspace?.path ?? "").isEmpty)
            let action = executor.execute(messageText)
            switch action {
            case .setSessionGoal(let goal):
                appState.setCurrentSessionGoal(goal)
                messageText = ""
                messageStore.append(Message(role: .assistant, content: "🎯 Goal set: \(goal)", isFinished: true))
                return
            case .showSessionGoal:
                let g = appState.currentSessionGoal ?? "(no goal set)"
                messageText = ""
                messageStore.append(Message(role: .assistant, content: "🎯 Current goal: \(g)", isFinished: true))
                return
            case .compactConversation:
                messageText = ""
                Task { await self.compactConversation(reason: "manual /compact") }
                return
            case .remember(let fact):
                messageText = ""
                Task { await self.rememberProjectFact(fact) }
                return
            case .gitRequiredError(let cmd):
                messageText = ""
                messageStore.append(Message(role: .assistant, content: "Command /\(cmd) needs a git repository in this workspace.", isFinished: true))
                return
            case .unknownCommand(let name, let available):
                messageText = ""
                messageStore.append(Message(role: .assistant, content: "Unknown command /\(name). Available: \(available.map { "/\($0)" }.joined(separator: ", "))", isFinished: true))
                return
            case .enterPlanMode, .openCommitComposer, .createPullRequest, .requestReview, .showContext:
                // E08 (Раздел 5 п.12-16): these used to fall through and send
                // the raw command text to the model. Each now performs its real
                // action: /plan switches agent mode, /commit opens the commit
                // composer, /pr creates a PR (or publish wizard without remote),
                // /review opens the review dialog, /context shows context.
                let path = appState.selectedWorkspace?.path ?? ""
                let hasGitRepo = !path.isEmpty
                var hasRemote = false
                if hasGitRepo {
                    hasRemote = !((try? GitRepository.remotes(in: path)) ?? []).isEmpty
                }
                let dispatchContext = SlashDispatchContext(
                    hasGitRepo: hasGitRepo,
                    hasRemote: hasRemote,
                    branch: appState.gitBranch,
                    modelID: appState.selectedModel,
                    providerID: appState.selectedProviderID,
                    agentMode: SessionSendLogic.sendMode(for: appState.agentMode),
                    workspacePath: path.isEmpty ? nil : path,
                    testRunner: hasGitRepo ? TestRunnerDetector.detect(in: path) : nil,
                    changedFileCount: appState.vcsChanges.count
                )
                for effect in SlashCommandDispatcher.effects(for: action, context: dispatchContext) {
                    applySlashEffect(effect)
                }
                return
            case .injectInstruction(let instruction):
                messageText = instruction
            case .passthrough:
                break
            }
        }
        // A send is already preparing its context; a second one would race
        // with it. The composer keeps the text and the input bar says why.
        guard !appState.isCompilingContext else { return }
        if let error = SendReadinessLogic.connectionValidationError(
            serverConnected: appState.serverConnected,
            selectedProviderID: appState.selectedProviderID,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected
        ) {
            let rejectedText = messageText
            let rejectedFiles = attachmentStore.attachedFiles
            let rejectedImages = attachmentStore.attachedImages
            recordRejectedSend(text: rejectedText, files: rejectedFiles, images: rejectedImages, error: error)
            messageText = ""
            clearDraft()
            attachmentStore.clear()
            restoreStashedDraftIfNeeded()
            return
        }
        if let error = SendReadinessLogic.sendValidationError(
            modelID: appState.selectedModel,
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            effectiveModelID: appState.effectiveSelectedModel()
        ) {
            let rejectedText = messageText
            let rejectedFiles = attachmentStore.attachedFiles
            let rejectedImages = attachmentStore.attachedImages
            recordRejectedSend(text: rejectedText, files: rejectedFiles, images: rejectedImages, error: error)
            messageText = ""
            clearDraft()
            attachmentStore.clear()
            restoreStashedDraftIfNeeded()
            return
        }
        
        let text = messageText
        let files = attachmentStore.attachedFiles
        let images = attachmentStore.attachedImages
        messageText = ""
        clearDraft()
        attachmentStore.clear()
        restoreStashedDraftIfNeeded()
        
        if appState.isLoading {
            messageQueue.enqueue(
                text: text,
                files: files,
                images: images,
                type: MessageType(from: appState.agentMode),
                sessionID: messageStore.currentSessionID ?? appState.selectedSession?.id
            )
            return
        }
        
        // Capture the target chat now: the task may start after the user has
        // already switched to another chat.
        let targetSessionID = messageStore.currentSessionID ?? appState.selectedSession?.id
        // Run the whole turn off the main actor so the UI never freezes while
        // the model/tools work (user directive 2026-10-30: интерфейс не
        // блокируется при отправке). UI updates inside hop back to main via
        // `MainActor.run`/`messageStore`.
        currentTask = Task.detached(priority: .userInitiated) {
            await sendDirectly(
                text: text,
                files: files,
                images: images,
                sessionID: targetSessionID
            )
        }
    }

    /// Move a queued message back into the composer. The draft that was already
    /// in the composer is stashed and restored after the edited message is sent.
    @MainActor
    func editQueuedMessage(_ queued: QueuedMessage) {
        guard messageQueue.remove(id: queued.id) != nil else { return }
        let current = ComposerDraftSnapshot(
            text: messageText,
            files: attachmentStore.attachedFiles,
            images: attachmentStore.attachedImages
        )
        if composerHoldsQueuedMessage, !current.isEmpty {
            // Switching edit targets: put the previously edited queued message
            // back instead of silently discarding it.
            messageQueue.enqueue(
                text: current.text,
                files: current.files,
                images: current.images,
                type: MessageType(from: appState.agentMode),
                sessionID: queued.sessionID
            )
        } else if stashedComposerDraft == nil, !current.isEmpty {
            stashedComposerDraft = current
        }
        messageText = queued.text
        attachmentStore.replaceImages(queued.images)
        attachmentStore.replaceFiles(queued.files)
        composerHoldsQueuedMessage = true
        restoreStashedDraftAfterSend = stashedComposerDraft != nil
        appState.inputFocusRequest += 1
    }

    /// Interrupt the current turn and send this queued message immediately.
    /// Remaining queued messages stay visible and resume after the forced send.
    @MainActor
    func forceSendQueued(_ queued: QueuedMessage) {
        guard messageQueue.pendingMessages.contains(where: { $0.id == queued.id }) else { return }
        let previousTask = currentTask
        messageQueue.pause()
        messageQueue.remove(id: queued.id)
        stopGeneration(cancelQueued: false)
        currentTask = Task { @MainActor in
            // Show the bubble BEFORE waiting for the interrupted turn. Waiting
            // first left the feed without the message for as long as the old
            // turn kept streaming; the user re-sent and the DB ended up with
            // duplicate user messages for one forced turn.
            await ForcedSendOrderingLogic.run(
                showUserMessage: { await appendOptimisticUserMessage(queued) },
                waitForPreviousTurn: { _ = await previousTask?.value },
                send: { optimisticID in
                    await sendDirectly(
                        text: queued.text,
                        files: queued.files,
                        images: queued.images,
                        agentModeOverride: queued.type.toAgentMode,
                        existingUserMessageID: optimisticID,
                        sessionID: queued.sessionID
                    )
                }
            )
            guard !Task.isCancelled else { return }
            messageQueue.resume()
            if !appState.isLoading {
                messageQueue.processNext()
            }
        }
    }

    /// Appends the user bubble for a forced send immediately, with the same
    /// session the send will use. Context parts and attachment payloads are
    /// filled in by `sendDirectly` once compilation finishes.
    @MainActor
    private func appendOptimisticUserMessage(_ queued: QueuedMessage) async -> String? {
        let route = currentRoute()
        let sessionID = await prepareSessionBeforeAppending(
            route: route,
            title: queued.text,
            sessionID: queued.sessionID
                ?? messageStore.currentSessionID
                ?? appState.selectedSession?.id
        )
        let message = Message(
            role: .user,
            content: queued.text,
            files: queued.files.isEmpty ? nil : queued.files,
            parts: MessagePartsBuilder.displayParts(text: queued.text, images: queued.images)
        )
        messageStore.append(message, to: sessionID)
        if messageStore.currentSessionID == nil, let sessionID {
            messageStore.currentSessionID = sessionID
        }
        if let sessionID,
           appState.selectedSession?.id == nil || appState.selectedSession?.id == sessionID,
           let preparedSession = appState.sessions.first(where: { $0.id == sessionID }) {
            appState.selectedSession = preparedSession
        }
        return message.id
    }

    private func restoreStashedDraftIfNeeded() {
        composerHoldsQueuedMessage = false
        guard restoreStashedDraftAfterSend, let draft = stashedComposerDraft else { return }
        messageText = draft.text
        attachmentStore.replaceImages(draft.images)
        attachmentStore.replaceFiles(draft.files)
        stashedComposerDraft = nil
        restoreStashedDraftAfterSend = false
    }

    /// Applies a slash-command effect to real app state (E08, Раздел 5 п.12-16).
    private func applySlashEffect(_ effect: SlashEffect) {
        switch effect {
        case .setAgentMode(let mode):
            switch mode {
            case "plan": appState.agentMode = .plan
            case "compose": appState.agentMode = .compose
            default: appState.agentMode = .build
            }
        case .appendAssistantMessage(let text):
            messageStore.append(Message(role: .assistant, content: text, isFinished: true))
        case .openGitAction(let uiAction):
            appState.pendingGitAction = uiAction
        case .injectInstruction(let instruction):
            messageText = instruction
        case .clearInput:
            messageText = ""
        }
    }
    
    // MARK: - Context compaction (/compact + auto at 90%)

    /// Routes that send the local feed as history can be compacted; server-
    /// managed routes (mimo serve, opencode serve, web, ACP) keep their own
    /// history, so replacing it locally would be a lie.
    private func supportsLocalHistoryCompaction(_ route: SendRoute) -> Bool {
        switch route {
        case .openAICompatible: return true
        default: return false
        }
    }

    private var selectedContextLimit: Int {
        let model = appState.effectiveSelectedModel()
        return ContextWindowCatalog.limit(for: model, reported: nil)
    }

    /// Measured over the MODEL-BOUND history so the badge drops right after a
    /// compaction instead of showing the whole visible feed.
    private var currentContextUsage: ContextUsage? {
        let history = ConversationCompactionLogic.historyForModel(messageStore.messages)
        guard !history.isEmpty else { return nil }
        return ContextUsageLogic.usage(messages: history, limitTokens: selectedContextLimit)
    }

    private func currentRoute() -> SendRoute {
        SendRouteResolver.route(
            selectedProviderID: appState.selectedProviderID,
            selectedModel: appState.effectiveSelectedModel(),
            serverConnected: appState.serverConnected,
            isACP: appState.isSelectedACPProvider,
            customProviders: appState.customProviders,
            localProviders: LocalProviderLogic.load(),
            webProviderIDs: appState.webProviderIDs
        )
    }

    /// Route-specific summarizer transport: a plain one-shot completion that
    /// never touches the visible chat (no streaming bubble, no tool protocol).
    private func summaryTransport(for route: SendRoute) -> ConversationSummarizer.Transport {
        switch route {
        case .openAICompatible(let baseURL, let apiKey, let model):
            return { prompt in
                let result = try await DirectChatClient.send(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: [DirectChatMessage(role: "user", content: prompt)]
                )
                return result.content
            }
        default:
            return { _ in throw ConversationSummarizerError.nothingToCompact }
        }
    }

    /// Replace the model-bound history with a factual summary message. The
    /// full chat stays visible; `historyForModel` cuts at the newest summary.
    @MainActor
    private func compactConversation(reason: String, sessionID: String? = nil) async {
        guard !isCompacting else { return }
        let targetSessionID = sessionID ?? messageStore.currentSessionID
        let history = ConversationCompactionLogic.historyForModel(
            messageStore.messages(in: targetSessionID)
        )
        guard ConversationCompactionLogic.plan(messages: history) != nil else {
            messageStore.append(Message(
                role: .assistant,
                content: ConversationSummarizerError.nothingToCompact.errorDescription ?? "Nothing to compact.",
                isFinished: true
            ), to: targetSessionID)
            return
        }
        let route = currentRoute()
        guard supportsLocalHistoryCompaction(route) else {
            messageStore.append(Message(
                role: .assistant,
                content: "Compaction is not available for this provider: its history is kept on the server (mimo/opencode serve, web or ACP), so a local summary would not shrink it.",
                isFinished: true
            ), to: targetSessionID)
            return
        }
        isCompacting = true
        defer { isCompacting = false }

        let beforeTokens = ContextUsageLogic.usedTokens(messages: history)
        let summarizer = ConversationSummarizer(transport: summaryTransport(for: route))
        do {
            let summary = try await summarizer.summarize(messages: history)
            messageStore.append(
                ConversationCompactionLogic.summaryMessage(summary: summary),
                to: targetSessionID
            )
            let afterTokens = ContextUsageLogic.estimateTokens(summary)
            messageStore.append(Message(
                role: .assistant,
                content: "Context compacted (\(reason)): \(history.count) messages summarized, ~\(ContextUsageLogic.formatTokens(beforeTokens)) → ~\(ContextUsageLogic.formatTokens(afterTokens)) tokens. The full chat stays visible; the model now continues from the summary.",
                isFinished: true
            ), to: targetSessionID)
        } catch {
            messageStore.append(Message(
                role: .assistant,
                content: "Context compaction failed: \(error.localizedDescription)",
                isFinished: true
            ), to: targetSessionID)
        }
    }

    /// Auto-compaction trigger (plan: 90% of the window). Runs before the
    /// outgoing history is built; failures never block the send.
    @MainActor
    private func autoCompactIfNeeded(route: SendRoute, sessionID: String?) async {
        guard supportsLocalHistoryCompaction(route) else { return }
        let history = ConversationCompactionLogic.historyForModel(
            messageStore.messages(in: sessionID)
        )
        guard !history.isEmpty else { return }
        let usage = ContextUsageLogic.usage(messages: history, limitTokens: selectedContextLimit)
        guard ContextUsageLogic.shouldCompact(usage) else { return }
        await compactConversation(reason: "auto at \(usage.percent)%", sessionID: sessionID)
    }

    func sendDirectly(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage] = [],
        agentModeOverride: AgentMode? = nil,
        retryCount: Int = 0,
        retryPlan: SessionBusyRetryLogic.RetryPlan? = nil,
        existingUserMessageID: String? = nil,
        sessionID explicitSessionID: String? = nil
    ) async {
        if let error = SendReadinessLogic.connectionValidationError(
            serverConnected: appState.serverConnected,
            selectedProviderID: appState.selectedProviderID,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected
        ) {
            await MainActor.run {
                self.recordRejectedSend(
                    text: text,
                    files: files,
                    images: images,
                    error: error,
                    existingUserMessageID: existingUserMessageID
                )
            }
            return
        }

        let assistantID = retryPlan?.assistantMessageID ?? UUID().uuidString
        let selectedID = retryPlan?.sessionID ?? appState.selectedSession?.id
        let messageID = retryPlan?.messageID ?? MessageIDGenerator.next()
        let agentMode = agentModeOverride ?? appState.agentMode
        let sendOptions = SessionSendLogic.buildSendOptions(
            agentMode: agentMode,
            selectedVariant: appState.selectedVariant.isEmpty ? nil : appState.selectedVariant,
            modelID: appState.effectiveSelectedModel(),
            selectedProviderID: appState.selectedProviderID,
            providers: appState.serverProviders,
            customProviders: appState.customProviders,
            messageID: messageID,
            accessLevel: appState.accessLevel,
            localProviderIDs: appState.localProviderIDs
        )
        if let error = SendReadinessLogic.sendValidationError(
            modelID: appState.selectedModel,
            providerID: sendOptions.providerID,
            effectiveModelID: appState.effectiveSelectedModel()
        ) {
            await MainActor.run {
                self.recordRejectedSend(
                    text: text,
                    files: files,
                    images: images,
                    error: error,
                    existingUserMessageID: existingUserMessageID
                )
                appState.isLoading = false
                appState.isStreaming = false
            }
            return
        }

        let localProviders = LocalProviderLogic.load()
        let route = SendRouteResolver.route(
            selectedProviderID: appState.selectedProviderID,
            selectedModel: appState.effectiveSelectedModel(),
            serverConnected: appState.serverConnected,
            isACP: appState.isSelectedACPProvider,
            customProviders: appState.customProviders,
            localProviders: localProviders,
            webProviderIDs: appState.webProviderIDs
        )
        // A turn belongs to the chat it was started in. Every `await` below
        // can span a chat switch (background generation), so the turn must
        // capture its session now and never read the visible one again.
        let turnSessionID: String? = explicitSessionID
            ?? retryPlan?.sessionID
            ?? messageStore.currentSessionID
            ?? appState.selectedSession?.id
        let capturedProjectRoot = appState.selectedWorkspace?.path ?? ""
        let capturedToolRoot = appState.toolWorkingDirectory
        let capturedModelID = appState.effectiveSelectedModel()
        let capturedParameters = ModelCallParametersStore.parameters(for: capturedModelID)
        // Auto-compact BEFORE any history is assembled for this turn (plan:
        // 90% of the model window). A failed summary is reported in-chat by
        // compactConversation and the send proceeds with the full history.
        await autoCompactIfNeeded(route: route, sessionID: turnSessionID)
        // Prior turns for context rules (user directive 2026-10-30): the FIRST
        // prompt of a chat collects no context; later prompts use the studied
        // data AND the chat history; project-less chats use the history as
        // their context. Computed BEFORE the user message is appended so the
        // current message never leaks into its own context.
        let priorTurnsForContext = await MainActor.run { () -> [ChatHistoryBuilder.Turn] in
            let msgs = messageStore.messages(in: turnSessionID)
            var history = ConversationCompactionLogic.historyForModel(msgs)
            // Retry / force-send: the current user message may already be in
            // the store; it is not part of the PRIOR turns.
            if (retryPlan != nil || existingUserMessageID != nil), !history.isEmpty {
                history.removeLast()
            }
            return history.map {
                ChatHistoryBuilder.Turn(role: roleString($0.role), content: $0.content, isFinished: $0.isFinished)
            }
        }
        // Every message collects context, including the first one in a chat
        // with an open project (user directive 2026-11-03). The send path
        // never scans the project here: it reads the already-built index, so
        // the "hour-long scan" that forced the old first-turn skip is gone.
        let needsContextPrep = true
        // Пользователь должен немедленно видеть результат отправки: сначала
        // создаём/выбираем сессию (запись в БД + сайдбар), открываем её и
        // пишем в чат отправленное сообщение. Сборка контекста и вызов
        // модели происходят ПОТОМ (user directive 2026-10-30).
        let earlyPreparedSessionID = await prepareSessionBeforeAppending(
            route: route,
            title: text,
            sessionID: turnSessionID
        )
        let sendSessionID = earlyPreparedSessionID ?? turnSessionID
        let earlySendModelID = sendOptions.modelID ?? appState.effectiveSelectedModel()
        let earlySendInfo = MessageSendInfo(
            parameters: ModelCallParametersStore.parameters(for: earlySendModelID),
            modelID: earlySendModelID,
            providerID: sendOptions.providerID,
            variant: sendOptions.variant,
            tools: [],
            sentAt: Date()
        )
        let earlyUserMessage = Message(
            role: .user,
            content: text,
            files: files.isEmpty ? nil : files,
            parts: MessagePartsBuilder.displayParts(text: text, images: images),
            sendInfo: earlySendInfo
        )
        var appendedUserMessageID: String?
        await MainActor.run {
            if messageStore.currentSessionID == nil, let sendSessionID {
                messageStore.currentSessionID = sendSessionID
            }
            switch SendUserMessageAppendLogic.action(
                hasRetryPlan: retryPlan != nil,
                existingUserMessageID: existingUserMessageID
            ) {
            case .appendNew:
                messageStore.append(earlyUserMessage, to: sendSessionID)
                appendedUserMessageID = earlyUserMessage.id
            case .updateExisting:
                // Force-send уже показал пузырь; контекст прикрепим позже.
                appendedUserMessageID = existingUserMessageID
            case .skip:
                break
            }
            if let earlyPreparedSessionID,
               let preparedSession = appState.sessions.first(where: { $0.id == earlyPreparedSessionID }),
               appState.selectedSession?.id == nil || appState.selectedSession?.id == sendSessionID {
                appState.selectedSession = preparedSession
            }
        }
        // The point context replaces the old auto-search block: the compiler
        // ranks the index, cites real lines and reports what it could not get.
        // It runs before the session is prepared, so a failure can degrade to
        // the raw message instead of blocking the send.
        let pointContextProjectRoot = capturedProjectRoot
        // A chat without a project has no project context to collect. Running
        // the collector with an empty root used to fire "Не удалось собрать
        // точечный контекст / Состояние задачи не сохранено" on every send in
        // "Без проекта". There is nothing to warn about: the send is complete
        // without project evidence.
        let hasProjectForContext = !pointContextProjectRoot.isEmpty
        // Do not scan the project or flash the loader when the feature is off.
        var pointContextRecords: [FileIndexRecord] = []
        var projectMemories: [ProjectMemoryChunk] = []
        var taskLedger: TaskLedger?
        var contextWarning: String?
        if appState.isPointContextEnabled && hasProjectForContext && needsContextPrep {
            await MainActor.run { appState.isCompilingContext = true }
            await MainActor.run {
                appState.contextPreparationStage = ContextStageLogLogic.line(for: .index)
            }
            pointContextRecords = await Self.recordsForPointContext(projectPath: pointContextProjectRoot)
            // Memory lives in the project database. A read failure must be
            // visible: sending without the facts the user saved would answer
            // from a wrong assumption.
            await MainActor.run {
                appState.contextPreparationStage = ContextStageLogLogic.line(
                    for: .memory,
                    detail: pointContextRecords.isEmpty ? "" : "файлов в индексе: \(pointContextRecords.count)"
                )
            }
            do {
                projectMemories = try await Task.detached(priority: .utility) {
                    try ProjectMemoryStore.loadChunks(projectPath: pointContextProjectRoot)
                }.value
            } catch {
                contextWarning = L.t(AppLocalizationKey.locMemoryLoadFailed)
            }

            // The ledger is append-only: it merges the persisted state with the
            // messages still visible, so a pruned feed cannot forget an earlier
            // constraint. Session ids are assigned before the first append, so
            // a brand-new session simply has no ledger yet.
            let ledgerSessionID = turnSessionID ?? ""
            if !ledgerSessionID.isEmpty {
                var persisted: TaskLedger?
                do {
                    persisted = try await Task.detached(priority: .utility) {
                        try TaskLedgerStore.load(
                            projectPath: pointContextProjectRoot,
                            sessionID: ledgerSessionID
                        )
                    }.value
                } catch {
                    contextWarning = [contextWarning, L.t(AppLocalizationKey.locLedgerFailed)]
                        .compactMap { $0 }.joined(separator: "\n")
                }

                let ledger = TaskLedgerExtraction.build(
                    sessionID: ledgerSessionID,
                    projectPath: pointContextProjectRoot,
                    goal: appState.currentSessionGoal,
                    messages: messageStore.messages(in: turnSessionID),
                    memories: projectMemories,
                    previous: persisted
                )
                taskLedger = ledger.isEmpty ? persisted : ledger

                if let taskLedger {
                    do {
                        try await Task.detached(priority: .utility) {
                            try TaskLedgerStore.save(taskLedger)
                        }.value
                    } catch {
                        contextWarning = [contextWarning, L.t(AppLocalizationKey.locLedgerFailed)]
                            .compactMap { $0 }.joined(separator: "\n")
                    }
                }
            }
        }
        // The optional local planner runs before compilation and only widens
        // the deterministic plan: it names entities from a bounded list, and
        // any failure is reported as a fallback instead of blocking the send.
        var localPlan: LocalQueryPlanResult?
        var preparedBoard: ContextBoard?
        if appState.isPointContextEnabled, appState.isLocalQueryPlannerEnabled,
           hasProjectForContext, needsContextPrep {
            // Board building extracts symbols/imports/tokens from every indexed
            // file — heavy CPU on the main actor froze the UI for seconds at
            // send start (user report 2026-10-30). Build it off-main.
            let board = await Task.detached(priority: .utility) {
                ContextBoardBuilder.build(
                    projectPath: pointContextProjectRoot,
                    records: pointContextRecords
                )
            }.value
            preparedBoard = board
            await MainActor.run { appState.isCompilingContext = true }
            // The local planner runs a local model and can take seconds — run
            // it off the main actor so the UI stays responsive while it works
            // (user directive 2026-10-29, §16.2).
            await MainActor.run {
                appState.contextPreparationStage = ContextStageLogLogic.line(for: .planning)
            }
            localPlan = await Task.detached(priority: .utility) {
                await TurnContextPlanningService.plan(
                    message: text,
                    board: board,
                    memories: projectMemories,
                    records: pointContextRecords,
                    priorTurns: priorTurnsForContext,
                    ledger: taskLedger
                )
            }.value
        }
        // Harness pass: a structural change ("хранилище переехало", "раздел
        // больше не нужен") must arrive with its reverse edges and the
        // questions that force a decision on each one. Deterministic host
        // work over the code graph — the internal model only widens the plan.
        var impactReport: ImpactReport?
        if appState.isPointContextEnabled, hasProjectForContext, needsContextPrep {
            await MainActor.run {
                appState.contextPreparationStage = ContextStageLogLogic.line(for: .impact)
            }
            let impactQuery = {
                let plan = ContextQueryPlanner.plan(for: text)
                return (plan.terms + plan.symbols).joined(separator: " ")
            }()
            // Бюджет обязателен: report() переиндексирует проект синхронно и
            // без предела. Живой прогон 2026-11-04 (чат FF5D0A17) встал на
            // этой стадии и ход не дал ответа вообще. Проход — необязательные
            // улики: по истечении бюджета идём дальше с тем графом, что есть.
            let impactRoot = pointContextProjectRoot
            let impactRecords = pointContextRecords
            let impactIntent = localPlan?.plan?.intent
            let impactTerms = (localPlan?.plan?.terms ?? []) + (localPlan?.plan?.symbols ?? []) + (localPlan?.plan?.files ?? [])
            let messageText = text
            let impactResult: ImpactReport?? = await ImpactBudget.runSync(budget: .seconds(ImpactBudget.defaultBudget)) { () -> ImpactReport? in
                do {
                    return try ImpactAnalyzer.report(
                        projectPath: impactRoot,
                        message: messageText,
                        query: impactQuery,
                        records: impactRecords,
                        intent: impactIntent,
                        semanticTerms: impactTerms
                    ) ?? ImpactAnalyzer.analyze(message: messageText, seeds: [], graph: .empty,
                                                 intent: impactIntent)
                } catch {
                    return ImpactAnalyzer.analyze(message: messageText, seeds: [], graph: .empty,
                                                  intent: impactIntent)
                }
            }
            impactReport = impactResult ?? nil
        }
        // The system instruction is built BEFORE the context is compiled: the
        // pack carries it, so the context viewer can show the whole payload
        // (system + point context + request) instead of only the evidence half.
        // It is still sent as its own system message, never inside the user
        // text, so nothing is duplicated on the wire.
        let turnProjectRoot = capturedToolRoot
        let turnParams = capturedParameters
        let webUserRules: String
        if case .web(let configID) = route {
            webUserRules = WebProviderStore.load().first(where: { $0.id == configID })?.systemPrompt ?? ""
        } else { webUserRules = "" }
        let sysPrompt = TurnDelivery.systemInstruction(
            route: route,
            userRules: [webUserRules, turnParams.systemPrompt ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            projectRoot: turnProjectRoot,
            isProject: !capturedProjectRoot.isEmpty,
            agentMode: agentMode
        )
        // Prior turns already computed above (before any potentially heavy
        // project scan) — do not recompute.
        await MainActor.run {
            appState.contextPreparationStage = ContextStageLogLogic.line(for: .files)
        }
        let preparation = await SendContextPreparationLogic.prepareAsync(
            message: text,
            records: pointContextRecords,
            projectPath: pointContextProjectRoot,
            isEnabled: appState.isPointContextEnabled,
            memories: projectMemories,
            ledger: taskLedger,
            extraWarning: contextWarning,
            localPlan: localPlan,
            board: preparedBoard,
            priorTurns: priorTurnsForContext,
            isPlanMode: agentMode == .plan,
            systemPrompt: sysPrompt,
            skillsDirectory: MyCoderPaths.skillsDir(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            impact: impactReport,
            onStage: { stage in
                // The compiler runs off the main actor; the composer line is
                // UI state. Hop back for each real stage instead of leaving
                // the graph/skills steps invisible (user directive п.2).
                let line = ContextStageLogLogic.line(for: stage)
                DispatchQueue.main.async {
                    appState.contextPreparationStage = line
                }
            }
        )
        if StreamDiagnostics.isEnabled {
            StreamDiagnostics.log(
                "[CTX] status=\(preparation.status) pack=\(preparation.pack.map { "\($0.text.utf8.count)B" } ?? "nil") modelText_bytes=\(preparation.modelText.utf8.count)",
                file: "/tmp/mycoder_agent.log"
            )
        }
        await MainActor.run {
            appState.contextPreparationStage = ContextStageLogLogic.doneLine(
                fileCount: preparation.pack?.manifest.included.count ?? 0,
                memoryCount: preparation.pack?.memoryIDs.count ?? 0,
                hasGraph: preparation.pack?.sections.contains { $0.title == "Граф кода" } ?? false,
                hasImpact: preparation.pack?.sections.contains { $0.title.contains("зависимостях") } ?? false
            )
            appState.isCompilingContext = false
        }
        let modelText: String
        switch route {
        case .openAICompatible, .web:
            modelText = preparation.modelText
        default:
            modelText = TurnDelivery.withSystem(sysPrompt, modelText: preparation.modelText)
        }
        let compiledParts = SendContextPreparationLogic.contextParts(preparation)
        let contextParts: [MessagePartContent] = compiledParts.isEmpty
            ? [.compiledContext(TurnDelivery.withSystem(sysPrompt, modelText: "## Запрос\n" + text))]
            : compiledParts
        // Сообщение уже показано заранее; теперь прикрепляем результат
        // сборки контекста к нему.
        if let appendedUserMessageID {
            await MainActor.run {
                self.messageStore.update(id: appendedUserMessageID) { message in
                    message.parts = MessagePartsBuilder.displayParts(text: text, images: images) + contextParts
                    message.contextSummary = SendContextPreparationLogic.summary(preparation)
                    message.sendInfo = earlySendInfo
                }
            }
        }
        // Everything below writes to this session, even if the user opened
        // another chat while the context was being prepared.
        if retryPlan == nil, let warning = preparation.warning {
            await MainActor.run {
                // Visible degradation: the send goes ahead with the raw
                // message, and the user is told why no context was added.
                messageStore.append(Message(
                    role: .assistant,
                    content: "⚠️ \(warning)",
                    isFinished: true
                ), to: sendSessionID)
            }
        }
        let parts = MessagePartsBuilder.build(text: modelText, files: files, images: images)
        await MainActor.run {
            currentAssistantMessageID = assistantID
            if retryPlan == nil {
                messageStore.append(
                    Message(id: assistantID, role: .assistant, content: "", isStreaming: true),
                    to: sendSessionID
                )
            } else {
                messageStore.update(id: assistantID) { message in
                    message.content = ""
                    message.isFinished = false
                    message.isStreaming = true
                }
            }
            appState.isLoading = true

            appState.isStreaming = true
            streamingText = ""
        }
        
        // Route was resolved before the first append, so every branch uses
        // the same stable local/remote session identity.
        // Round 8 P3: a `.none` route must never fall through into the serve
        // branch. Surface the reason and stop instead of a silent no-op.
        if let routeError = SendRouteGuard.errorMessage(for: route, serverConnected: appState.serverConnected) {
            await MainActor.run {
                appState.isLoading = false
                appState.isStreaming = false
                sseClient.disconnect()
                messageStore.update(id: assistantID) { msg in
                    msg.content = routeError
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                currentAssistantMessageID = nil
            }
            return
        }

        do {
            // ── Local `opencode serve` branch (OC-3) ──────────
            // The user's own authenticated server: session REST API with
            // basic auth, NOT OpenAI /v1. Serve sessions persist server-side;
            // reuse ours per chat so follow-ups keep context.
            if case .openCodeServe(let baseURL, let headers, let providerID, let model) = route {
                let chatKey = earlyPreparedSessionID ?? assistantID
                await MainActor.run {
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = SendStatusText.waitingForResponse(modelID: model, providerName: "OpenCode")
                    }
                }
                let sid = OpenCodeServeSessionStore.shared.sessionID(for: chatKey)
                var streamed = ""
                var promptAcceptedSID: String? = nil
                do {
                    // Prefer SSE streaming (prompt_async + /event); fall back
                    // to the blocking call when the stream yields nothing
                    // (e.g. older serve without prompt_async).
                    let (streamSID, stream) = try await OpenCodeServeClient.streamSend(
                        baseURL: baseURL, headers: headers, modelID: model,
                        text: modelText, providerID: providerID, sessionID: sid
                    )
                    promptAcceptedSID = streamSID
                    OpenCodeServeSessionStore.shared.remember(sessionID: streamSID, for: chatKey)
                    for try await event in stream {
                        streamed += event.text
                        let snapshot = streamed
                        await MainActor.run {
                            self.messageStore.update(id: assistantID) { msg in
                                msg.content = snapshot
                                msg.isStreaming = true
                            }
                        }
                    }
                } catch {
                    guard !streamed.isEmpty else {
                        throw error
                    }
                }
                if streamed.isEmpty {
                    // The prompt may already be processing server-side, so a
                    // blind re-send would duplicate the user message: read back
                    // the session first, and re-send only when the server has
                    // nothing for it.
                    if let activeSID = promptAcceptedSID,
                       let recovered = await OpenCodeServeClient.fetchLastAssistantText(
                        baseURL: baseURL, headers: headers, sessionID: activeSID
                       ) {
                        OpenCodeServeSessionStore.shared.remember(sessionID: activeSID, for: chatKey)
                        streamed = recovered
                    } else {
                        let result = try await RequestRetryPolicy.withRetries {
                            try await OpenCodeServeClient.send(
                                baseURL: baseURL, headers: headers, modelID: model,
                                text: modelText, providerID: providerID, sessionID: sid
                            )
                        }
                        OpenCodeServeSessionStore.shared.remember(sessionID: result.sessionID, for: chatKey)
                        streamed = result.content
                    }
                }
                let finalText = streamed
                await MainActor.run {
                    self.appState.isLoading = false
                    self.appState.isStreaming = false
                    self.streamingText = ""
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = finalText
                        msg.isFinished = true
                        msg.isStreaming = false
                    }
                    self.currentAssistantMessageID = nil
                }
                return
            }

            // ── Local / custom OpenAI-compatible branch ──────────
            if case .openAICompatible(let baseURL, let apiKey, let model) = route {
                let params = ModelCallParametersStore.parameters(for: model)
                // Prior turns = everything except the just-appended user message
                // and the empty assistant placeholder (audit P1 — carry history).
                let prior = await MainActor.run { () -> [ChatHistoryBuilder.Turn] in
                    let msgs = messageStore.messages(in: sendSessionID)
                    let modelHistory = ConversationCompactionLogic.historyForModel(msgs)
                    let history = modelHistory.count >= 2 ? Array(modelHistory.dropLast(2)) : []
                    // A long transcript is replaced by the ledger inside
                    // `modelText`; do not also send twenty raw turns.
                    guard !SendContextPreparationLogic.replacesRawHistory(
                        preparation,
                        priorTurnCount: history.count
                    ) else { return [] }
                    return history.map { ChatHistoryBuilder.Turn(role: roleString($0.role), content: $0.content, isFinished: $0.isFinished) }
                }
                // E01 (Раздел 9 п.10(c)): carry REAL image bytes to the direct
                // OpenAI-compatible path — they used to be silently dropped.
                let directParts = MessagePartsBuilder.build(text: modelText, files: files, images: images)
                    .compactMap { part -> [String: Any]? in
                        if part["type"] as? String == "text" {
                            return ["type": "text", "text": part["text"] as? String ?? ""]
                        }
                        if part["type"] as? String == "file",
                           let mime = part["mime"] as? String,
                           MessagePartsBuilder.isImageMimeType(mime),
                           let url = part["url"] as? String {
                            return ["type": "image_url", "image_url": ["url": url]]
                        }
                        return nil
                    }
                // Tool-protocol preamble with the full tool list must reach ANY
                // delivery path as the SYSTEM message, otherwise free/API models
                // reply "I have no file access" because they never saw a tool list.
                // Built once, before context compilation, so the pack and the
                // wire carry the same instruction — see `sysPrompt` above.
                let projectRoot = appState.toolWorkingDirectory
                let msgs = ChatHistoryBuilder.messages(
                    systemPrompt: sysPrompt, priorTurns: prior, userText: modelText,
                    parts: directParts.isEmpty ? nil : directParts
                )
                // Round 8 P4: show a visible waiting state (the old flow left an
                // empty streaming bubble with no indication for up to 120 s).
                let providerName = appState.customProviders.first(where: { $0.id == appState.selectedProviderID })?.name
                await MainActor.run {
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = SendStatusText.waitingForResponse(modelID: model, providerName: providerName)
                    }
                }
                // Direct local/OpenAI-compatible models do not execute tools
                // server-side. Run the same text-protocol loop used by the
                // the selected project, and its result is fed back so the
                // model can continue instead of stopping at a raw ```tool block.
                // Мост браузера обязателен: без него browser_fetch отвечает
                // «bridge not available» даже при живом движке (живой прогон
                // 2026-11-04: mercury-3 ушёл на web_fetch).
                var executor = ProjectWebToolExecutor.bridged(
                    projectRoot: projectRoot,
                    accessLevel: appState.accessLevel,
                    sessionId: sendSessionID
                )
                executor.subagentLauncher = subagentLauncher(
                    projectRoot: projectRoot,
                    transport: .openAICompatible(baseURL: URL(string: baseURL) ?? URL(fileURLWithPath: "/"), apiKey: apiKey ?? "", model: model),
                    sessionID: sendSessionID
                )
                let maxIterations = 15
                var conversation = msgs
                var finalText = ""
                var finalUsage: UsageCapture? = nil
                /// Raw server events across every iteration (debug button).
                var allRawEvents: [String] = []
                // Thinking channel across iterations (`reasoning_content` /
                // `reasoning` / `thinking`). It used to be dropped, so the
                // reasoning spoiler stayed empty on direct providers.
                var reasoningChunks: [String] = []
                var reasoningStartedAt: Date?
                // Chronological timeline: reasoning of an iteration, then the
                // calls that iteration requested. Keeping it interleaved is
                // what makes the chat show "thinking → tool → thinking → tool"
                // instead of one merged thinking block above every call.
                var timelineParts: [MessagePartContent] = []
                do {
                    for iteration in 0..<maxIterations {
                        let result = try await RequestRetryPolicy.withRetries {
                            try await streamDirectChat(
                                baseURL: baseURL,
                                apiKey: apiKey,
                                model: model,
                                messages: conversation,
                                parameters: params,
                                assistantID: assistantID,
                                timelineParts: timelineParts
                            )
                        }
                        let response = result.content
                        finalUsage = result.usage
                        allRawEvents.append(contentsOf: result.rawEvents)
                        if StreamDiagnostics.isEnabled {
                            StreamDiagnostics.log(
                                "[ITER] \(iteration) reasoning_bytes=\(result.reasoning?.utf8.count ?? 0) content_bytes=\(response.utf8.count)",
                                file: "/tmp/mycoder_agent.log"
                            )
                        }
                        if let reasoning = result.reasoning, !reasoning.isEmpty {
                            if reasoningStartedAt == nil { reasoningStartedAt = Date() }
                            reasoningChunks.append(reasoning)
                            timelineParts.append(.reasoning(reasoning))
                        }
                        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
                        if calls.isEmpty || WebToolProtocolEmulator.shouldStopLoop(
                            iteration: iteration, maxIterations: maxIterations, lastResponse: response
                        ) {
                            if calls.isEmpty, let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: response) {
                                conversation.append(DirectChatMessage(role: "assistant", content: response))
                                conversation.append(DirectChatMessage(role: "user", content: feedback))
                                continue
                            }
                            finalText = response
                            break
                        }
                        // Fix the model's prose for this iteration BEFORE its
                        // tool calls so no server response is lost: the order is
                        // reasoning → prose → calls → results → next iteration.
                        let iterationProse = WebToolProtocolEmulator.strippingToolFences(from: response)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !iterationProse.isEmpty {
                            timelineParts.append(.text(iterationProse))
                        }
                        let prepared = prepareLocalToolCalls(
                            calls,
                            modelContext: response,
                            projectRoot: projectRoot,
                            accessLevel: appState.accessLevel,
                            isPlanMode: agentMode == .plan
                        )
                        for item in prepared {
                            timelineParts.append(.toolCall(
                                name: item.call.name,
                                args: item.argsSummary,
                                result: item.validationError.map {
                                    WebToolProtocolEmulator.validationResultText(for: $0, callName: item.call.name)
                                },
                                callID: item.callID
                            ))
                        }
                        publishToolParts(
                            AssistantTurnPartsLogic.directTimelineParts(
                                timeline: timelineParts,
                                answer: ""
                            ),
                            assistantID: assistantID
                        )
                        enqueueLocalToolApprovals(
                            prepared.compactMap(\.approval),
                            assistantID: assistantID
                        )

                        var resultsBlock = ""
                        for item in prepared {
                            guard !Task.isCancelled else { break }
                            // Plan mode: mutating tools are refused without a
                            // prompt — report the denial back to the model.
                            if let reason = item.denialReason {
                                resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                    name: item.call.name, result: reason
                                ) + "\n"
                                timelineParts.append(.toolCall(
                                    name: item.call.name,
                                    args: item.argsSummary,
                                    result: reason,
                                    callID: item.callID
                                ))
                                continue
                            }
                            if let validationError = item.validationError {
                                switch await resolveOutOfProjectAccess(item, assistantID: assistantID) {
                                case .allowed(let grantedRoots):
                                    if let error = WebToolProtocolEmulator.validate(
                                        item.call,
                                        projectRoot: projectRoot,
                                        accessLevel: appState.accessLevel,
                                        grantedRoots: grantedRoots
                                    ) {
                                        resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                            name: item.call.name,
                                            result: WebToolProtocolEmulator.validationResultText(for: error, callName: item.call.name)
                                        ) + "\n"
                                        continue
                                    }
                                case .denied(let message):
                                    resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                        name: item.call.name, result: message
                                    ) + "\n"
                                    timelineParts = localToolParts(
                                        timelineParts,
                                        settingResult: message,
                                        callID: item.callID
                                    )
                                    publishToolParts(
                                        AssistantTurnPartsLogic.directTimelineParts(
                                            timeline: timelineParts,
                                            answer: ""
                                        ),
                                        assistantID: assistantID
                                    )
                                    continue
                                case .notApplicable:
                                    resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                        name: item.call.name,
                                        result: WebToolProtocolEmulator.validationResultText(for: validationError, callName: item.call.name)
                                    ) + "\n"
                                    continue
                                }
                            }
                            if let approval = item.approval {
                                let approved = await awaitLocalToolApproval(
                                    approval,
                                    assistantID: assistantID
                                )
                                guard !Task.isCancelled else { break }
                                guard approved else {
                                    let denial = "user denied permission: \(item.call.name) was not executed. Do not retry the same operation; ask the user how to proceed."
                                    resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                        name: item.call.name, result: denial
                                    ) + "\n"
                                    timelineParts = localToolParts(
                                        timelineParts,
                                        settingResult: denial,
                                        callID: item.callID
                                    )
                                    publishToolParts(
                                        AssistantTurnPartsLogic.directTimelineParts(
                                            timeline: timelineParts,
                                            answer: ""
                                        ),
                                        assistantID: assistantID
                                    )
                                    continue
                                }
                            }
                            let toolResult = await executor.execute(item.call, userApproved: true)
                            guard !Task.isCancelled else { break }
                            if StreamDiagnostics.isEnabled {
                                StreamDiagnostics.log(
                                    "[TOOL] \(item.call.name) result_bytes=\(toolResult.utf8.count)",
                                    file: "/tmp/mycoder_agent.log"
                                )
                            }
                            resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                name: item.call.name, result: toolResult
                            ) + "\n"
                            timelineParts = localToolParts(
                                timelineParts,
                                settingResult: toolResult,
                                callID: item.callID
                            )
                            publishToolParts(
                                AssistantTurnPartsLogic.directTimelineParts(
                                    timeline: timelineParts,
                                    answer: ""
                                ),
                                assistantID: assistantID
                            )
                        }
                        conversation.append(DirectChatMessage(role: "assistant", content: response))
                        conversation.append(DirectChatMessage(role: "user", content: resultsBlock))
                        finalText = response
                        await MainActor.run {
                            let reasoning = DirectChatClient.mergedReasoning(reasoningChunks)
                            self.messageStore.update(id: assistantID) { msg in
                                msg.content = response + "\n\n⏳ Running tools..."
                                msg.parts = AssistantTurnPartsLogic.directTimelineParts(
                                    timeline: timelineParts,
                                    answer: ""
                                )
                                msg.reasoning = reasoning ?? ""
                                msg.reasoningStartedAt = reasoningStartedAt
                                msg.isStreaming = true
                            }
                        }
                    }
                    await MainActor.run {
                        let reasoning = DirectChatClient.mergedReasoning(reasoningChunks)
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        self.streamingText = ""
                        self.messageStore.update(id: assistantID) { msg in
                            msg.content = finalText
                            msg.usage = finalUsage
                            msg.rawResponses = allRawEvents.isEmpty ? nil : allRawEvents
                            msg.parts = AssistantTurnPartsLogic.directTimelineParts(
                                timeline: timelineParts,
                                answer: finalText
                            )
                            msg.reasoning = reasoning ?? ""
                            msg.reasoningStartedAt = reasoningStartedAt
                            msg.reasoningEndedAt = reasoning == nil ? nil : Date()
                            msg.isFinished = true
                            msg.isStreaming = false
                        }
                        self.currentAssistantMessageID = nil
                    }
                } catch {
                    await MainActor.run {
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        if Task.isCancelled || error is CancellationError {
                            // Stop pressed: keep whatever already streamed in
                            // instead of replacing it with an error.
                            self.messageStore.update(id: assistantID) { msg in
                                msg.isFinished = true
                                msg.isStreaming = false
                                if msg.content.isEmpty {
                                    msg.content = L.t(AppLocalizationKey.locGenerationStopped)
                                }
                            }
                        } else {
                            self.messageStore.update(id: assistantID) { msg in
                                msg.content = "Local model error: \(error.localizedDescription)"
                                msg.isFinished = true
                                msg.isStreaming = false
                            }
                        }
                        self.currentAssistantMessageID = nil
                    }
                }
                return
            }


            // ── Web-chat provider branch (browser tool-emulation) ─
            if case .web(let configID) = route {
                guard let cfg = WebProviderStore.load().first(where: { $0.id == configID }) else {
                    // Round 8 R2: the web config was deleted after selection —
                    // surface it instead of falling through into the serve branch.
                    let missing = SendRouteGuard.webConfigMissingMessage(configID: configID)
                    await MainActor.run {
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        self.messageStore.update(id: assistantID) { msg in
                            msg.content = missing ?? "The web provider is no longer configured."
                            msg.isFinished = true
                            msg.isStreaming = false
                        }
                        self.currentAssistantMessageID = nil
                    }
                    return
                }
                let chatID = sendSessionID ?? assistantID
                activeWebChatID = chatID
                await runWebChatTurn(config: cfg, text: modelText, assistantID: assistantID, chatID: chatID, preparedSystemPrompt: sysPrompt)
                return
            }

            // ── ACP provider branch ──────────────────────────────
            // Custom ACP providers (custom.type == .acp) and auto-detected
            // local ACP providers both land here via the resolver's `.acp`
            // route. The old code only handled the custom case, so a detected
            // ACP provider fell through into the serve branch and never sent.
            let acpClient: ACPClient?
            if case .acp = route,
               let local = localProviders.first(where: { $0.id == appState.selectedProviderID && $0.isEnabled }) {
                acpClient = ACPClient(baseURLString: local.apiBaseURL)
            } else {
                acpClient = appState.isSelectedACPProvider ? appState.acpClient : nil
            }
            if let acpClient = acpClient {
                // Build ACP request messages from user text + files
                let acpMessages = buildACPMessages(text: modelText, files: files, images: images)
                let acpAgent = SessionSendLogic.sendMode(for: agentModeOverride ?? appState.agentMode)
                let acpVariant = appState.selectedVariant.isEmpty ? nil : appState.selectedVariant

                // Non-streaming send via ACP client (E06: parameters must
                // actually reach the ACP model, they used to be dropped).
                // Empty responses are transient: retry before surfacing.
                let response = try await RequestRetryPolicy.withRetries {
                    try await acpClient.sendChatCompletion(
                        messages: acpMessages,
                        model: appState.selectedModel,
                        agent: acpAgent,
                        variant: acpVariant,
                        parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel()),
                        stream: false
                    )
                }

                // Convert ACP response to message text and reject a blank completion.
                let responseText = response.choices.first?.message.content ?? ""
                guard ProviderResponseValidationLogic.hasVisibleContent(responseText) else {
                    throw ACPError.emptyResponse
                }
                let reasoningText = response.choices.first?.message.reasoning
                let acpUsage = response.usage.map {
                    UsageCapture(acpUsage: $0, modelID: response.model,
                                 providerID: appState.selectedProviderID.isEmpty ? "acp" : appState.selectedProviderID)
                }

                await MainActor.run {
                    self.appState.isLoading = false
                    self.appState.isStreaming = false
                    self.streamingText = ""
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = responseText
                        msg.reasoning = reasoningText ?? ""
                        msg.usage = acpUsage
                        msg.isFinished = true
                        msg.isStreaming = false
                    }
                    self.currentAssistantMessageID = nil
                    // No session for ACP — task complete is still useful
                    self.appState.notificationService.taskCompleted(
                        sessionTitle: String(text.prefix(50)),
                        sessionID: assistantID
                    )
                }
                return
            }

            // ── Standard MiMo Serve branch ───────────────────────
            await MainActor.run {
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = SendStatusText.thinkingPlaceholder(modelID: self.appState.effectiveSelectedModel())
                }
                self.startServeTimeout(assistantID: assistantID)
            }
            guard let sessionID = sendSessionID
                    ?? messageStore.currentSessionID
                    ?? appState.selectedSession?.id
                    ?? selectedID else {
                throw MimoServeError.httpError(statusCode: 0)
            }

            // Do not re-pin the visible chat: the user may have opened another
            // one while this turn was being prepared.
            
            await MainActor.run {
                sseClient.onEvent = { type, payload in
                    Task { @MainActor in
                        self.handleSSEEvent(type: type, payload: payload)
                    }
                }
            }
            
            if let url = URL(string: "http://127.0.0.1:\(appState.serverPort)/global/event") {
                sseClient.connect(url: url)
            }
            
            let responseMessages = try await appState.mimoClient.sendMessage(
                sessionID: sessionID,
                parts: parts,
                options: sendOptions,
                parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel())
            )
            appState.scheduleGitRefresh(sessionID: sessionID)
            
            let firstResponse = SessionSendLogic.assistantResponse(from: responseMessages)
            let reasoningText = firstResponse?.parts?.compactMap { part -> String? in
                if case .reasoning(let value) = part { return value }
                return nil
            }.joined(separator: "\n") ?? ""
            let hasToolActivity = firstResponse?.parts?.contains { part in
                if case .toolInvocation = part { return true }
                return false
            } ?? false
            if ServeResponseFeedbackLogic.failureMessage(
                responseCount: responseMessages.count,
                text: firstResponse?.textContent,
                reasoning: reasoningText,
                hasToolActivity: hasToolActivity
            ) != nil {
                throw MimoServeError.emptyResponse
            }

            await MainActor.run {
                let hasPendingQuestion = self.appState.pendingQuestionRequest?.sessionID == sessionID
                let mergedParts = messageStore.message(id: self.currentAssistantMessageID ?? "")?.parts ?? []
                let waitingForQuestion = hasPendingQuestion || PlanQuestionLogic.hasPendingQuestions(in: mergedParts)

                if SessionSendLogic.shouldAwaitSSE(
                    responseMessages: responseMessages,
                    hasPendingQuestion: waitingForQuestion
                ) {
                    return
                }

                if !waitingForQuestion {
                    self.serveTimeoutTask?.cancel()
                    self.serveTimeoutTask = nil
                    self.sseClient.disconnect()
                }

                if let firstResponse {
                    let merged = MessageResponseMergeLogic.mergedAssistantMessage(
                        existing: messageStore.message(id: self.currentAssistantMessageID ?? "") ?? Message(role: .assistant, content: ""),
                        serverParts: firstResponse.parts,
                        serverText: firstResponse.textContent,
                        streamingText: self.streamingText
                    )
                    self.streamingText = merged.content
                    self.messageStore.update(id: self.currentAssistantMessageID ?? "") { msg in
                        msg.content = merged.content
                        msg.reasoning = merged.reasoning
                        msg.parts = merged.parts
                        msg.isFinished = !waitingForQuestion
                        msg.isStreaming = waitingForQuestion
                    }
                    self.syncExecutionSteps(from: merged.parts)
                }

                if waitingForQuestion {
                    self.appState.isLoading = false
                    self.appState.isStreaming = false
                } else {
                    self.appState.isLoading = false
                    self.appState.isStreaming = false
                    self.streamingText = ""
                    self.currentAssistantMessageID = nil
                    self.appState.scheduleGitRefresh(sessionID: sendSessionID)
                    // Notify: task complete. The turn belongs to its own chat,
                    // which may not be the one currently on screen.
                    if let session = self.appState.sessions.first(where: { $0.id == sessionID }) {
                        self.appState.notificationService.taskCompleted(
                            sessionTitle: session.title,
                            sessionID: session.id
                        )
                    }
                }
            }
        } catch {
            if case MimoServeError.sessionBusy = error {
                await MainActor.run {
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = retryCount < 3 ? "Session busy, aborting and retrying..." : "Session busy after \(retryCount + 1) attempts, giving up."
                        msg.isStreaming = true
                    }
                    self.appState.notificationService.sessionBusy()
                }
                if let sessionID = sendSessionID ?? selectedID,
                   !sessionID.isEmpty {
                    let currentPlan = SessionBusyRetryLogic.RetryPlan(
                        retryCount: retryCount,
                        sessionID: sessionID,
                        assistantMessageID: assistantID,
                        messageID: messageID
                    )
                    if let nextPlan = SessionBusyRetryLogic.nextPlan(
                        from: currentPlan,
                        isCancelled: Task.isCancelled
                    ) {
                        guard !Task.isCancelled else { return }
                        try? await appState.mimoClient.abortSession(id: sessionID)
                        guard !Task.isCancelled else { return }
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        await sendDirectly(
                            text: text,
                            files: files,
                            images: images,
                            agentModeOverride: agentModeOverride,
                            retryCount: nextPlan.retryCount,
                            retryPlan: nextPlan
                        )
                        return
                    }
                }
            }
            let isServeRoute: Bool
            if case .mimoServe = route {
                isServeRoute = true
            } else {
                isServeRoute = false
            }
            let serveDisconnected = ServeTransportFailureLogic.shouldMarkServerDisconnected(
                isServeRoute: isServeRoute,
                error: error
            )
            let userFacingError = serveDisconnected
                ? ServeTransportFailureLogic.disconnectedMessage
                : "Error: \(error.localizedDescription)"
            await MainActor.run {
                self.serveTimeoutTask?.cancel()
                self.serveTimeoutTask = nil
                self.appState.isLoading = false
                self.appState.isStreaming = false
                self.sseClient.disconnect()
                if serveDisconnected {
                    self.appState.serverConnected = false
                    self.appState.notificationService.serverDisconnected()
                }
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = userFacingError
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                self.appState.scheduleGitRefresh(sessionID: sendSessionID)
            }
        }
    }

    /// Direct OpenAI-compatible turn with real token streaming. The answer is
    /// written into its own chat's feed as it arrives, so switching chats no
    /// longer hides the text until the whole response is ready. Providers that
    /// reject `stream: true` fall back to the plain request.
    private func streamDirectChat(
        baseURL: String,
        apiKey: String?,
        model: String,
        messages: [DirectChatMessage],
        parameters: ModelCallParameters,
        assistantID: String,
        timelineParts: [MessagePartContent]
    ) async throws -> DirectChatResult {
        do {
            return try await DirectChatStreamer.stream(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: messages,
                parameters: parameters
            ) { update in
                let reasoning = update.reasoning.isEmpty ? nil : update.reasoning
                self.messageStore.update(id: assistantID) { msg in
                    if !update.content.isEmpty {
                        msg.content = update.content
                    }
                    if let reasoning {
                        msg.reasoning = reasoning
                        if msg.reasoningStartedAt == nil {
                            msg.reasoningStartedAt = Date()
                        }
                    }
                    msg.parts = AssistantTurnPartsLogic.directStreamingParts(
                        timeline: timelineParts,
                        reasoning: reasoning,
                        answer: update.content
                    )
                    msg.isStreaming = true
                }
            }
        } catch let error as DirectChatError {
            // A provider that does not implement SSE answers 400/405/422/501.
            if case .http(let status, _) = error,
               [400, 405, 422, 501].contains(status) {
                return try await DirectChatClient.send(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: messages,
                    parameters: parameters
                )
            }
            throw error
        }
    }

    private func startServeTimeout(assistantID: String) {
        serveTimeoutTask?.cancel()
        serveTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.appState.isLoading,
                      self.currentAssistantMessageID == assistantID else { return }
                self.sseClient.disconnect()
                self.appState.isLoading = false
                self.appState.isStreaming = false
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = "The local agent did not finish this request within 90 seconds. Check MiMo Serve and try again."
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                self.currentAssistantMessageID = nil
                self.serveTimeoutTask = nil
            }
        }
    }

    /// One assistant message can have several gated calls. They are all
    /// registered and rendered before the loop starts awaiting them, so the
    /// user sees the full queue instead of one modal at a time.

    private func subagentLauncher(
        projectRoot: String,
        transport: SubagentRunner.Transport,
        sessionID: String?
    ) -> (String, String) async -> String {
        let parentSessionID = sessionID
            ?? messageStore.currentSessionID
            ?? appState.selectedSession?.id
            ?? ""
        let projectKey = appState.selectedWorkspace?.id ?? ChatSession.standaloneProjectKey
        let directory = appState.selectedWorkspace?.path ?? ChatSession.standaloneProjectKey
        let context = SubagentRunner.Context(
            parentSessionID: parentSessionID,
            projectKey: projectKey,
            directory: directory,
            projectRoot: projectRoot,
            transport: transport
        )
        return { description, prompt in
            await SubagentRunner.launch(description: description, prompt: prompt, context: context)
        }
    }

    private func prepareLocalToolCalls(
        _ calls: [WebToolCall],
        modelContext: String,
        projectRoot: String,
        accessLevel: AccessLevel,
        isPlanMode: Bool
    ) -> [PreparedLocalToolCall] {
        calls.map { call in
            let callID = UUID().uuidString
            var validationError = WebToolProtocolEmulator.validate(
                call, projectRoot: projectRoot, accessLevel: accessLevel
            )
            if call.arguments["__mycoder_truncated"] == "1", validationError == nil {
                validationError = .incompleteJSON
            }
            // Plan mode is read-only: mutating tools are refused right away,
            // without a security prompt (user directive 2026-10-30).
            var denialReason: String?
            if case .deny(let reason) = PlanModeToolPolicy.decision(
                for: call, isPlanMode: isPlanMode
            ) {
                denialReason = reason
            }
            var approval: PendingToolApproval?
            if case .pathEscapesProject(let path) = validationError {
                // The path lies outside the project folder. The user is asked
                // for access instead of dead-ending the call with a validation
                // error the model can only apologize about.
                approval = PendingToolApproval(
                    callID: callID,
                    tool: call.name,
                    message: OutOfProjectAccessLogic.approvalMessage(
                        tool: call.name,
                        path: path,
                        projectRoot: projectRoot
                    ),
                    accessGrant: OutOfProjectAccessLogic.grantRoot(forPath: path)
                )
            } else if validationError == nil,
                      WebToolAccessGate.permission(for: call, accessLevel: accessLevel) == .requireApproval {
                let details = WebToolApprovalDetails(
                    call: call,
                    projectRoot: projectRoot,
                    modelContext: modelContext
                )
                approval = PendingToolApproval(
                    callID: callID,
                    tool: call.name,
                    message: details.formattedMessage
                )
            }
            return PreparedLocalToolCall(
                call: call,
                callID: callID,
                validationError: validationError,
                approval: denialReason == nil ? approval : nil,
                denialReason: denialReason
            )
        }
    }

    /// Outcome of an out-of-project access request.
    private enum OutOfProjectAccessOutcome {
        case allowed(grantedRoots: [String])
        case denied(message: String)
        case notApplicable
    }

    /// Ask the user for access to a folder outside the project folder.
    ///
    /// A path outside the project is not a dead end: the user decides. An
    /// approved grant lets the call run, a refusal is reported back to the
    /// model as a denial (so it stops retrying and asks the user instead).
    @MainActor
    private func resolveOutOfProjectAccess(
        _ item: PreparedLocalToolCall,
        assistantID: String
    ) async -> OutOfProjectAccessOutcome {
        guard case .pathEscapesProject(let path)? = item.validationError else {
            return .notApplicable
        }
        guard let approval = item.approval else { return .notApplicable }
        let approved = await awaitLocalToolApproval(approval, assistantID: assistantID)
        guard !Task.isCancelled else { return .notApplicable }
        guard approved else {
            return .denied(message: OutOfProjectAccessLogic.denialMessage(
                tool: item.call.name,
                path: path
            ))
        }
        return .allowed(grantedRoots: [approval.accessGrant].compactMap { $0 })
    }

    @MainActor
    private func enqueueLocalToolApprovals(
        _ approvals: [PendingToolApproval],
        assistantID: String
    ) {
        guard !approvals.isEmpty else { return }
        let sessionID = messageStore.currentSessionID
            ?? appState.selectedSession?.id
            ?? ""
        let sessionTitle = appState.sessions.first(where: { $0.id == sessionID })?.title
            ?? appState.selectedSession?.title
            ?? "myCoder"
        for approval in approvals {
            ToolApprovalCenter.shared.register(
                approval,
                sessionID: sessionID,
                assistantID: assistantID
            )
            appState.notificationService.add(AppNotification(
                id: approval.id,
                title: "Tool approval needed",
                message: "\(approval.tool) is waiting in \(sessionTitle). Allow or deny it in the chat.",
                type: .warning,
                action: sessionID.isEmpty
                    ? nil
                    : .openMessage(sessionID: sessionID, messageID: assistantID)
            ))
        }
        messageStore.update(id: assistantID) { msg in
            let existing = Set(msg.pendingApprovals.map(\.id))
            msg.pendingApprovals.append(contentsOf: approvals.filter { !existing.contains($0.id) })
            msg.isStreaming = true
        }
        MyCoderAPIServer.appendLog(
            "⏸ queued local tool approvals: " + approvals.map { "\($0.tool) id=\($0.id)" }.joined(separator: ", ")
        )
        playLocalApprovalSound()
    }

    @MainActor
    private func awaitLocalToolApproval(
        _ approval: PendingToolApproval,
        assistantID: String
    ) async -> Bool {
        let approved = await ToolApprovalCenter.shared.awaitVerdict(id: approval.id)
        messageStore.update(id: assistantID) { msg in
            msg.pendingApprovals.removeAll { $0.id == approval.id }
            msg.isStreaming = true
        }
        appState.notificationService.remove(approval.id)
        MyCoderAPIServer.appendLog(
            "⏸ local tool approval resolved: \(approval.tool) approved=\(approved) id=\(approval.id)"
        )
        return approved
    }

    @MainActor
    private func reattachPendingApprovals(sessionID: String) {
        let assistantIDs = Set(
            messageStore.messages
                .filter { $0.role == .assistant }
                .map(\.id)
        )
        let grouped = ToolApprovalCenter.shared.pendingApprovals(matchingAssistantIDs: assistantIDs)
        guard !grouped.isEmpty else { return }
        messageStore.setPendingApprovals(grouped)
    }

    @MainActor
    private func publishToolParts(
        _ parts: [MessagePartContent],
        assistantID: String,
        content: String? = nil
    ) {
        messageStore.update(id: assistantID) { msg in
            msg.parts = parts
            if let content { msg.content = content }
            msg.isStreaming = true
        }
    }

    private func playLocalApprovalSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func stopGeneration() {
        stopGeneration(cancelQueued: true)
    }

    func stopGeneration(cancelQueued: Bool) {
        // The running turn belongs to the chat it was started in; stopping it
        // must abort that session even if the user is reading another one.
        let turnSessionID = messageStore.sessionID(owningMessageID: currentAssistantMessageID ?? "")
            ?? messageStore.currentSessionID
            ?? appState.selectedSession?.id
        currentTask?.cancel()
        currentTask = nil
        // A direct-model turn may be suspended on queued approvals. Deny
        // only this chat's queue; approvals in other chats keep waiting.
        if let sessionID = turnSessionID {
            let pendingIDs = ToolApprovalCenter.shared.pendingApprovals(in: sessionID).map(\.id)
            ToolApprovalCenter.shared.cancelPending(in: sessionID)
            for id in pendingIDs {
                appState.notificationService.remove(id)
            }
            messageStore.setPendingApprovals([:])
        }
        serveTimeoutTask?.cancel()
        serveTimeoutTask = nil
        sseClient.disconnect()
        if cancelQueued {
            messageQueue.cancelAll()
            messageQueue.resume()
        }

        #if canImport(WebKit)
        if let providerID = activeWebProviderID {
            let projectID = appState.selectedWorkspace?.id
                ?? appState.selectedWorkspace?.path
                ?? "global"
            let chatID = activeWebChatID
                ?? messageStore.currentSessionID
                ?? appState.selectedSession?.id
                ?? "provider-default"
            Task { @MainActor in
                await appState.stopWebGeneration(
                    providerID: providerID,
                    projectID: projectID,
                    chatID: chatID
                )
            }
        }
        #endif

        if let sessionID = turnSessionID {
            Task {
                try? await appState.mimoClient.abortSession(id: sessionID)
            }
        }

        appState.isLoading = false
        appState.isStreaming = false
        
        if let id = currentAssistantMessageID {
            messageStore.update(id: id) { msg in
                msg.isFinished = true
                msg.isStreaming = false
                if msg.content.isEmpty {
                    msg.content = L.t(AppLocalizationKey.locGenerationStopped)
                }
            }
        }
        
        currentAssistantMessageID = nil
        streamingText = ""
        appState.notificationService.generationStopped()
        appState.scheduleGitRefresh(sessionID: turnSessionID)
    }
    
    /// The user message the navigator should mark as current: resolved from
    /// the reported row frames against the visible viewport band.
    private func updateCurrentVisibleUserMessage() {
        currentUserMessageID = UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: chatViewportFrame.height > 0 ? chatViewportFrame : nil,
            frames: userRowFrames,
            messages: displayMessages
        )
    }

    /// Loads one older page and keeps the reader's current question in place.
    /// Without this anchor, prepending rows pushes the visible turn down and
    /// the chat appears to jump to unrelated history.
    func loadOlderMessages(proxy: ScrollViewProxy) {
        guard let sessionID = messageStore.currentSessionID else { return }
        guard !messageStore.isLoadingOlder else { return }  // Prevent cascade
        let anchorMessageID = currentUserMessageID ?? displayMessages.last(where: { $0.role == .user })?.id

        Task {
            canLoadOlderMessages = false
            _ = await messageStore.loadHistory(sessionID: sessionID, client: appState.mimoClient)
            // Local/auto-free sessions have no server history — page the local
            // DB when the server yielded nothing, otherwise older messages are
            // unreachable after the initial tail load.
            if !messageStore.hasMoreMessages {
                await MainActor.run { _ = messageStore.loadOlderFromDatabase(sessionId: sessionID) }
            }
            await MainActor.run {
                canLoadOlderMessages = messageStore.hasMoreMessages
                guard let anchorMessageID else { return }
                // The new page needs one layout pass before `scrollTo` can
                // resolve the anchor row inside the lazy stack.
                DispatchQueue.main.async {
                    proxy.scrollTo(anchorMessageID, anchor: .top)
                }
            }
        }
    }

    func loadMessageIntoComposer(_ message: Message) {
        let draft = MessageEditLogic.draft(from: message)
        messageText = draft.text
        attachmentStore.replaceImages(draft.images)
        attachmentStore.replaceFiles(draft.files)
    }

    func resendMessage(_ message: Message) {
        guard MessageEditLogic.canResend(message) else { return }
        let draft = MessageEditLogic.draft(from: message)
        guard MessageSendValidation.canSend(
            text: draft.text,
            images: draft.images,
            files: draft.files
        ) else { return }

        if appState.isLoading {
            messageQueue.enqueue(
                text: draft.text,
                files: draft.files,
                images: draft.images,
                type: MessageType(from: appState.agentMode),
                sessionID: messageStore.currentSessionID ?? appState.selectedSession?.id
            )
            return
        }

        Task {
            await sendDirectly(
                text: draft.text,
                files: draft.files,
                images: draft.images,
                sessionID: messageStore.currentSessionID ?? appState.selectedSession?.id
            )
        }
    }

    // MARK: - ACP Message Building

    /// Builds `[ACPRequestMessage]` from the user's text, file references and
    /// images. Uses ACPMessageBuilder so real image bytes (data URLs) are sent
    /// instead of a "[N image(s) attached]" placeholder (plan Раздел 9 Блок 2).
    /// Run one turn against a web-chat provider through an in-app WKWebView
    /// bridge + WebChatDriver, presenting events (streaming/tool/captcha/final)
    /// into the chat so the message actually reaches the web model and shows a
    /// real response (plan Раздел 12). Restores the captured session cookies.
    @MainActor
    private func runWebChatTurn(config: WebProviderConfig,
                                text: String,
                                assistantID: String,
                                chatID: String,
                                preparedSystemPrompt: String? = nil) async {
        #if canImport(WebKit)
        // Reconcile selections created before the unified web-selection contract
        // existed. The browser must use the same model and effort the composer
        // shows, even for an old config saved by a previous build.
        var effectiveConfig = config
        let availableModels = WebProviderConnectivity.models(for: config)
        let routedWebModel = appState.effectiveSelectedModel()
        effectiveConfig.selectedModel = availableModels.contains(routedWebModel)
            ? routedWebModel
            : WebProviderSelectionLogic.effectiveSelectedModel(
                for: config,
                availableModels: availableModels
            )
        effectiveConfig.effort = appState.selectedWebEffort ?? .medium
        if effectiveConfig != config {
            WebProviderStore.save(WebProviderStore.upsert(effectiveConfig, in: WebProviderStore.load()))
        }
        activeWebProviderID = effectiveConfig.id

        // AntiBrowser: один движок, одна вкладка на чат. Повторный вход в
        // тот же чат переиспользует запомненную вкладку браузера.
        let projectID = appState.selectedWorkspace?.id ?? appState.selectedWorkspace?.path ?? "global"
        let refreshKey = "\(effectiveConfig.id)|\(projectID)|\(chatID)"
        webCatalogRefreshKeys.remove(refreshKey)

        do {
            try EngineStatusCenter.shared.requireEngine()
        } catch {
            appendWebStatus(to: assistantID, line: error.localizedDescription)
            messageStore.update(id: assistantID) { m in
                m.content = error.localizedDescription
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }
        let tabKey = AntiBrowserTabManager.makeKey(providerID: effectiveConfig.id,
                                                  projectID: projectID,
                                                  chatID: chatID)
        let bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        // Показываем мини-каст вкладки этого чата внутри приложения.
        appState.showWebBrowserPanel(for: effectiveConfig, projectID: projectID, chatID: chatID)
        // Resolve vendor-specific selectors from the catalog.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: effectiveConfig.vendor.id)
        let selectors = WebVendorSelectors(
            input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
            sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='end'], button[data-testid='send-button'], .send-button-container",
            responseContainer: catalogEntry?.responseContainer ?? "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: catalogEntry?.stopButton ?? ".send-button-container.stop, button[aria-label*='top'], button[data-testid='stop-button'], button[class*='stop']"
        )

        // Restore cookies captured at login so the session is authenticated.
        // Use the chatID (session ID) for cookie restoration to match the webview session.
        let sessionID = chatID
        var restorationPayload: WebSessionRestorationPayload?
        if let store = WebSessionManager.restore(providerId: effectiveConfig.id,
                                                 homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                 sessionID: sessionID) {
            do {
                let payload = WebSessionRestorationLogic.payload(from: store)
                try await bridge.setCookies(payload.cookies)
                restorationPayload = payload
            } catch {
                appendWebStatus(to: assistantID, line: "Failed to restore the saved session: \(error.localizedDescription)")
            }
        }
        do {
            // Audit 2026-09-08/09: host-only matching kept turns running on
            // the wrong PRODUCT surface. Require the surface matching the
            // selected model (Kimi K3/K3 Swarm live on /agent — navigating
            // "back" to the chat URL resets the choice to Fast and blocks
            // the send; plain chat models must NOT sit on /agent).
            let currentURL = (try? await bridge.currentURL()) ?? ""
            let onChatSurface = !currentURL.isEmpty && WebChatSurfaceLogic.isChatSurface(
                urlString: currentURL,
                chatURL: effectiveConfig.chatURL,
                vendor: effectiveConfig.vendor,
                selectedModel: effectiveConfig.selectedModel
            )
            if !onChatSurface {
                // Kimi agent models (K3/K3 Swarm) live on /agent: a fresh or
                // drifted webview must land THERE, not on the plain chat URL
                // (which would reset the choice to Fast).
                try await bridge.navigate(to: WebChatSurfaceLogic.targetSurfaceURL(
                    chatURL: effectiveConfig.chatURL,
                    vendor: effectiveConfig.vendor,
                    selectedModel: effectiveConfig.selectedModel
                ))
            }
            if let payload = restorationPayload, !payload.localStorage.isEmpty {
                do {
                    try await bridge.setLocalStorage(payload.localStorage)
                    let reloadURL = (try? await bridge.currentURL()) ?? effectiveConfig.chatURL
                    try await bridge.navigate(to: reloadURL)
                } catch {
                    appendWebStatus(to: assistantID, line: "Saved cookies restored, but localStorage could not be restored: \(error.localizedDescription)")
                }
            }

            // Wait for chat interface to be ready (input element present).
            // Some sites need extra time to hydrate the chat UI after auth restore.
            var ready = false
            for _ in 0..<30 {
                if (try? await bridge.exists(selector: selectors.input)) ?? false {
                    ready = true
                    break
                }
                await bridge.wait(ms: 500)
            }
            if !ready {
                appendWebStatus(to: assistantID, line: "Chat input not found — page may need manual login.")
            }
        } catch {
            messageStore.update(id: assistantID) { m in
                m.content = "Could not open \(effectiveConfig.chatURL): \(error.localizedDescription). Check that the site is reachable and you are logged in."
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }

        // SmartSend fallback: try direct API or smart element detection first
        // AFTER the page is loaded and ready. If it succeeds, the message was
        // already sent, so we skip the standard driver.runTurn() typing/clicking
        // but still need to wait for the response.
        // Round 30b: capture the response fingerprint BEFORE submitting — the
        // answer may be fully rendered by the time the driver reads its
        // baseline (binding + injection take seconds), and a post-send baseline
        // would make awaitResponse wait for changes that never come.
        let preSendFingerprint = (try? await bridge.responseFingerprint(selector: selectors.responseContainer)) ?? ""
        // Audit 2026-09-08: SmartSend submits the RAW user text, but on the
        // FIRST turn of a mapped conversation the tool-protocol preamble MUST
        // reach the model — without it live models answer "I have no file
        // access" (Qwen evidence) and the agent loop never starts. Prepend the
        // same preamble runTurn would have used; runTurn receives skipSend and
        // will not duplicate it.
        let smartSendWorkspacePath = appState.toolWorkingDirectory
        let webTurnSystemPrompt = preparedSystemPrompt ?? WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: effectiveConfig.systemPrompt,
            projectRoot: smartSendWorkspacePath,
            directory: smartSendWorkspacePath,
            isGitRepo: (try? GitRepository.repositoryRoot(for: smartSendWorkspacePath)) != nil
        )
        let smartSendMessage = TurnDelivery.withSystem(webTurnSystemPrompt, modelText: text)
        let smartSendResult = await trySmartSendFallback(
            config: effectiveConfig, bridge: bridge, message: smartSendMessage
        )
        let skipDriverSend = smartSendResult.success
        if smartSendResult.success {
            appendWebStatus(to: assistantID, line: "Sent via \(smartSendResult.winningMethod ?? "smart-fallback"), waiting for response…")
        }

        // Round 8 P4: give immediate visible feedback while the page loads and
        // the first turn is sent (the old flow left an empty bubble).
        messageStore.update(id: assistantID) { m in
            if m.content.isEmpty {
                let model = effectiveConfig.selectedModel.isEmpty ? effectiveConfig.displayName : effectiveConfig.selectedModel
                m.content = SendStatusText.thinkingPlaceholder(modelID: model)
            }
        }

        // Do not open the model dropdown during send. Model discovery is an
        // explicit user action in the settings sheet; opening it here can leave
        // the page menu mounted and make an effort control look like the model.
        // The driver now applies only the persisted modelButton and effortDropdown.

        // E09/E10: real tool operations feed the project's undo stack and
        // request_history — pass the per-project undo manager + session so
        // write/edit tool calls snapshot, record undo entries and history rows.
        // E12: run_command executes only at .fullAccess (gate enforced here).
        let workspacePath = appState.toolWorkingDirectory
        // Shared approval mailbox: the driver posts requests here and blocks
        // in awaitAnswer until the user resolves the Allow/Deny card.
        let approvalBox = WebToolApprovalBox()
        activeApprovalBox = approvalBox
        var executor = ProjectWebToolExecutor(
            projectRoot: workspacePath,
            undoManager: (try? ProjectUndoManager(projectPath: workspacePath)),
            sessionId: messageStore.currentSessionID,
            accessLevel: appState.accessLevel
        )
        executor.bridge = bridge
        executor.selectors = selectors
        let driver = WebChatDriver(bridge: bridge, executor: executor, selectors: selectors,
                                   config: effectiveConfig, projectRoot: workspacePath, accessLevel: appState.accessLevel,
                                   approvalBox: approvalBox, preparedSystemPrompt: webTurnSystemPrompt)

        // Whether this local chat ever started a remote session — must be
        // known BEFORE binding: a first turn must open a genuinely fresh
        // remote chat, never land in the currently-open conversation.
        let preBindKey = appState.webRemoteChatKey(for: effectiveConfig,
                                                   projectID: projectID,
                                                   chatID: chatID)
        let isFirstTurnForBinding = appState.webSessionIsFirstTurn(preBindKey)
        let remoteMapping: WebRemoteChatMapping?
        do {
            remoteMapping = try await bindWebRemoteChat(driver: driver,
                                                        bridge: bridge,
                                                        config: effectiveConfig,
                                                        projectID: projectID,
                                                        chatID: chatID,
                                                        freshSubmitPending: skipDriverSend,
                                                        isFirstTurn: isFirstTurnForBinding)
        } catch {
            appState.recordWebBrowserAction(action: "remote_chat_binding_failed",
                                            config: effectiveConfig,
                                            projectID: projectID,
                                            chatID: chatID,
                                            modelID: effectiveConfig.selectedModel,
                                            effort: appState.selectedWebEffort,
                                            detail: error.localizedDescription)
            messageStore.update(id: assistantID) { m in
                m.content = "Web chat was not sent: \(error.localizedDescription)"
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }
        appState.recordWebBrowserAction(action: "send_started",
                                        config: effectiveConfig,
                                        projectID: projectID,
                                        chatID: chatID,
                                        modelID: effectiveConfig.selectedModel,
                                        effort: appState.selectedWebEffort,
                                        remoteChatID: remoteMapping?.remoteChatID,
                                        detail: remoteMapping == nil
                                            ? "WKWebView background send; remote chat id will be bound after the first message lands (SPA vendor)"
                                            : "WKWebView background send bound to verified remote chat")

        // Send the tool-protocol preamble only on the first mapped conversation;
        // later turns continue exactly that remote conversation.
        let bindingKey = remoteMapping?.key ?? appState.webRemoteChatKey(for: effectiveConfig,
                                                                         projectID: projectID,
                                                                         chatID: chatID)
        let isFirst = appState.webSessionIsFirstTurn(bindingKey)
        appState.markWebSessionStarted(bindingKey)
        let retrySignal = WebChatRetrySignal()
        let approvalSignal = WebChatApprovalSignal()
        let completionSignal = WebChatCompletionSignal()
        // Live tool-call parts for THIS assistant message: each toolCall event
        // appends a part (result == nil → running); the matching toolResult
        // fills it in. The final answer lands in m.content, so spoilers and
        // answer text never overwrite each other.
        let toolPartsBox = WebToolPartsBox()
        // User directive 2026-09-11: NOTHING the model produced may be wiped
        // from the chat. Kimi streams "thinking" prose first, then the answer;
        // tool rounds produce an answer after each round. Every accepted
        // text snapshot is kept in the accumulator and displayed as
        // previous-content + latest snapshot, so early reasoning survives.
        let textAccumulator = WebTurnTextAccumulator()
        let presentEvent: (WebChatEvent) -> Void = { event in
            completionSignal.recordIfCompleted(event)
            if case .approvalRequired(_, let message) = event {
                approvalSignal.record(message)
            }
            if let reason = self.webCatalogRefreshReason(for: event) {
                retrySignal.record(reason)
            }
            switch event {
            case .toolCall(let call):
                MyCoderAPIServer.appendLog("🧰 web toolCall: \(call.name) args=\(call.arguments)")
            case .toolResult(let name, let result):
                MyCoderAPIServer.appendLog("🧰 web toolResult: \(name) len=\(result.count)")
            default:
                break
            }
            Task { @MainActor in
                let presentation = WebChatEventPresenter.present(event)
                switch WebCaptchaPresentationLogic.action(for: event) {
                case .showSolver:
                    if case .captcha(_, let note) = presentation {
                        self.captchaSolverContext = WebCaptchaSolverContext(bridge: bridge, note: note)
                    }
                case .dismissSolver:
                    self.captchaSolverContext = nil
                case .none:
                    break
                }
                switch event {
                case .streaming(let text):
                    // Live partial answer: APPEND to everything the model has
                    // produced this turn (user directive 2026-09-11: never
                    // erase earlier thinking/answers) — a growing snapshot of
                    // the SAME message extends it, a NEW message after tool
                    // rounds starts a fresh block. Tool spoilers persist.
                    let merged = textAccumulator.absorb(text)
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.content = merged
                        m.isStreaming = true
                        if !toolParts.isEmpty { m.parts = toolParts }
                    }
                case .toolCall(let call):
                    // A tool round finished: close the current text block so
                    // the post-tool answer does not graft onto it.
                    textAccumulator.closeBlock()
                    let partID = UUID().uuidString
                    toolPartsBox.appendRunning(
                        name: call.name,
                        args: call.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                        partID: partID
                    )
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.parts = toolParts
                        m.isStreaming = true
                    }
                case .toolResult(let name, let result):
                    toolPartsBox.completeLast(name: name, result: result)
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.parts = toolParts
                        m.isStreaming = true
                    }
                case .approvalRequest(let request):
                    // Interactive Allow/Deny card: the driver is blocked in
                    // awaitAnswer until the user resolves it.
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        if !toolParts.isEmpty { m.parts = toolParts }
                        m.pendingApprovalID = request.id
                        m.pendingApprovalTool = request.tool
                        m.pendingApprovalMessage = request.message
                        m.isStreaming = true
                    }
                default:
                    switch WebChatTurnMutation.mutation(for: presentation) {
                    case .replaceText(let t, let finished, let streaming):
                        // Final answer: keep the accumulated thinking/answers
                        // and APPEND the final block (user directive
                        // 2026-09-11: nothing produced may be erased).
                        let merged = textAccumulator.absorbFinal(t)
                        self.messageStore.update(id: assistantID) { m in
                            m.content = merged; m.isFinished = finished; m.isStreaming = streaming
                            // Keep the tool spoilers: parts survive the
                            // final answer instead of being wiped.
                            if !toolPartsBox.parts.isEmpty { m.parts = toolPartsBox.parts }
                        }
                        self.finishWebTurn()
                    case .appendStatus(let line):
                        self.messageStore.update(id: assistantID) { m in
                            m.content = m.content.isEmpty ? line : "\(m.content)\n\(line)"
                            m.isStreaming = false
                            if !toolPartsBox.parts.isEmpty { m.parts = toolPartsBox.parts }
                        }
                        if WebChatEventPresenter.blocksUntilUserAction(event) || line.contains("fresh session") {
                            self.appState.resetWebSession(bindingKey)
                        }
                    case .none:
                        break
                    }
                }
            }
        }
        print("🔄 [ChatPanelView] Calling driver.runTurn with skipSend=\(skipDriverSend)")
        await driver.runTurn(userMessage: text, isFirstMessage: isFirst, emit: presentEvent,
                             skipSend: skipDriverSend,
                             preSendFingerprint: skipDriverSend ? preSendFingerprint : nil)
        print("🔄 [ChatPanelView] driver.runTurn completed")
        guard !WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: Task.isCancelled) else {
            finishWebTurn()
            return
        }

        // Injection failures happen before typing. Refresh the same live page
        // once, reload the persisted model/profile snapshot, and retry exactly
        // once; never create a second assistant bubble or a second remote chat.
        var finalConfig = effectiveConfig
        // Audit 2026-09-08 (Kimi SPA): when binding was postponed, capture the
        // remote chat id AFTER the send — the page URL/DOM gains it once the
        // first message lands. Later turns then navigate to this conversation.
        // The SPA updates its URL asynchronously after submit; binding
        // immediately can capture a STALE id (live: sidebar top link of the
        // previous chat). Wait for the URL to carry a chat id first.
        var boundMapping = remoteMapping
        if boundMapping == nil {
            for _ in 0..<20 {
                let currentURL = (try? await bridge.currentURL()) ?? ""
                if SendSubmissionPolicy.urlHasChatID(currentURL) { break }
                await bridge.wait(ms: 500)
            }
            // Bind ONLY when the URL itself carries the id (see second
            // binding attempt below for why sidebar candidates are stale).
            // The id comes from the same approved URL string (no live re-read).
            if let remote = await currentRemoteChat(bridge: bridge,
                                                 config: effectiveConfig),
               SendSubmissionPolicy.urlHasChatID(remote.url) {
                let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                    baseURL: remote.url,
                    vendor: effectiveConfig.vendor,
                    chatID: remote.id
                ) ?? remote.url
                boundMapping = WebRemoteChatMapping(key: bindingKey,
                                                    remoteChatID: remote.id,
                                                    remoteURL: canonical,
                                                    verifiedTitle: appState.selectedSession?.title)
                appState.saveWebRemoteChatMapping(boundMapping!)
            }
        }
        if let approvalMessage = approvalSignal.take() {
            appState.recordWebBrowserAction(action: "send_blocked_approval",
                                            config: effectiveConfig,
                                            projectID: projectID,
                                            chatID: chatID,
                                            modelID: effectiveConfig.selectedModel,
                                            effort: appState.selectedWebEffort,
                                            remoteChatID: boundMapping?.remoteChatID,
                                            detail: approvalMessage)
            messageStore.update(id: assistantID) { message in
                message.isFinished = true
                message.isStreaming = false
            }
            finishWebTurn()
            return
        }
        if retrySignal.take() != nil {
            appendWebStatus(to: assistantID, line: "Refreshing model catalog before retry…")
            self.appState.resetWebSession(bindingKey)
            _ = await appState.refreshWebModelsAndEffort(for: effectiveConfig,
                                                         projectID: projectID,
                                                         chatID: chatID)
            let refreshedConfig = WebProviderStore.load().first(where: { $0.id == effectiveConfig.id }) ?? effectiveConfig
            finalConfig = refreshedConfig
            if !refreshedConfig.discoveredModels.isEmpty {
                let retryDriver = WebChatDriver(bridge: bridge, executor: executor, selectors: selectors,
                                                config: refreshedConfig, projectRoot: workspacePath,
                                                accessLevel: appState.accessLevel, preparedSystemPrompt: webTurnSystemPrompt)
                await retryDriver.runTurn(
                    userMessage: text,
                    isFirstMessage: WebRetryContextLogic.isFirstMessageForRetry(originalIsFirst: isFirst),
                    emit: presentEvent
                )
                guard !WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: Task.isCancelled) else {
                    finishWebTurn()
                    return
                }
            } else {
                appendWebStatus(to: assistantID, line: "Model catalog refresh returned no selectable models; retry stopped.")
            }
        }
        guard completionSignal.take() else {
            appendWebStatus(to: assistantID, line: "Web chat did not produce a verified final answer; the send was not marked complete. Check the browser session and retry.")
            finishWebTurn()
            return
        }
        // Audit 2026-09-08: bind ONLY when the URL itself carries the id —
        // sidebar DOM candidates can be a stale previous chat (live: Kimi
        // bound 1a07fa07 while the real chat was 1a0808b4). The id comes from
        // the same approved URL string (no live re-read across commits).
        if boundMapping == nil,
           let remote = await currentRemoteChat(bridge: bridge,
                                                 config: effectiveConfig),
           SendSubmissionPolicy.urlHasChatID(remote.url) {
            let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: remote.url,
                vendor: effectiveConfig.vendor,
                chatID: remote.id
            ) ?? remote.url
            boundMapping = WebRemoteChatMapping(key: bindingKey,
                                                remoteChatID: remote.id,
                                                remoteURL: canonical,
                                                verifiedTitle: appState.selectedSession?.title)
            appState.saveWebRemoteChatMapping(boundMapping!)
        }
        appState.recordWebBrowserAction(action: "send_completed",
                                        config: finalConfig,
                                        projectID: projectID,
                                        chatID: chatID,
                                        modelID: finalConfig.selectedModel,
                                        effort: appState.selectedWebEffort,
                                        remoteChatID: boundMapping?.remoteChatID,
                                        detail: "WebChatDriver completed")
        messageStore.update(id: assistantID) { message in
            let effortLabel = appState.selectedWebEffort?.displayName ?? "not supported"
            let remoteID = boundMapping?.remoteChatID ?? "pending"
            // User directive 2026-09-08: route metadata must NEVER be part of
            // the answer text. It ships as a routeInfo part rendered as chips
            // in the message header (provider · model · effort · remote chat).
            let chips: [String] = [
                finalConfig.displayName,
                finalConfig.selectedModel.isEmpty ? "auto" : finalConfig.selectedModel,
                "effort \(effortLabel)",
                "chat \(remoteID)"
            ]
            var routeParts = message.parts
            routeParts.removeAll { if case .routeInfo = $0 { return true } else { return false } }
            routeParts.append(.routeInfo(chips: chips))
            message.parts = routeParts
        }
        finishWebTurn()
        #else
        messageStore.update(id: assistantID) { m in
            m.content = "Web providers require WebKit (macOS)."; m.isFinished = true; m.isStreaming = false
        }
        #endif
    }

    /// Try SmartSend fallback before standard web chat driver.
    ///
    /// Attempts to send via:
    /// 1. Direct API (if network requests captured)
    /// 2. Smart element detection (if elements found)
    /// 3. Falls back to standard browser automation
    ///
    /// - Parameters:
    ///   - config: Web provider configuration
    ///   - bridge: Browser automation bridge
    ///   - message: Message to send
    /// - Returns: SmartSend result
    private func trySmartSendFallback(
        config: WebProviderConfig,
        bridge: BrowserAutomationBridge,
        message: String
    ) async -> SmartSendResult {
        await SmartSend.execute(
            message: message,
            config: config,
            bridge: bridge,
            appState: appState
        )
    }

    @MainActor
    /// Binding contract:
    /// - Existing mapping → navigate to that remote chat (must verify) —
    ///   later turns continue exactly that conversation.
    /// - Fresh chat with a visible remote id → reuse it.
    /// - Fresh chat with NO id (audit 2026-09-08, Kimi SPA): return nil and
    ///   let the caller send first, then bind the id the page gains after the
    ///   send. Blocking the FIRST send because a URL has no id yet made Kimi
    ///   unusable; context mixing is impossible on a brand-new conversation.
    /// - freshSubmitPending (SmartSend already submitted): NEVER click "New
    ///   Chat" — the SPA URL may lag behind the submit and wiping the fresh
    ///   conversation (live: ChatGPT submit verified, then startNewSession
    ///   navigated home and discarded it).
    /// Current remote conversation from the live page URL — the single
    /// authoritative source for binding (audit 2026-09-08). Sidebar DOM
    /// candidates are NEVER used here: without a matching URL they are links
    /// to some other conversation (live: ChatGPT bound "WEB:f8f76…" and Kimi
    /// bound a previous chat while the real chat was created after the send).
    /// The id is derived from the SAME url string (no live re-read race).
    private func currentRemoteChat(bridge: BrowserAutomationBridge,
                                   config: WebProviderConfig) async -> (id: String, url: String)? {
        guard let currentURL = try? await bridge.currentURL(),
              let host = URL(string: currentURL)?.host,
              host == URL(string: config.chatURL)?.host,
              let id = WebRemoteChatIdentityLogic.chatIDFromURL(currentURL),
              !id.isEmpty else { return nil }
        return (id, currentURL)
    }

    private func bindWebRemoteChat(driver: WebChatDriver,
                                   bridge: BrowserAutomationBridge,
                                   config: WebProviderConfig,
                                   projectID: String,
                                   chatID: String,
                                   freshSubmitPending: Bool = false,
                                   isFirstTurn: Bool = false) async throws -> WebRemoteChatMapping? {
        let key = appState.webRemoteChatKey(for: config, projectID: projectID, chatID: chatID)
        let providerHost = URL(string: config.chatURL)?.host
        if var existing = appState.webRemoteChatMapping(for: config, projectID: projectID, chatID: chatID) {
            guard URL(string: existing.remoteURL)?.host == providerHost else {
                throw WebChatError.remoteChatBindingFailed("Stored remote chat belongs to another provider host; sending was blocked.")
            }
            let currentID = try? await driver.getCurrentChatID()
            if currentID != existing.remoteChatID {
                try await bridge.navigate(to: existing.remoteURL)
                try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
            }
            guard try await driver.getCurrentChatID() == existing.remoteChatID else {
                throw WebChatError.remoteChatBindingFailed("The browser did not verify the stored remote chat UUID after navigation; sending was blocked.")
            }
            existing.lastUsedAt = Date()
            existing.status = "verified"
            appState.saveWebRemoteChatMapping(existing)
            return existing
        }

        // Round 30: reuse an already-open remote conversation BEFORE creating a
        // new one. SmartSend may have just submitted into a fresh chat whose
        // URL now carries /chat/{id} or /c/{id}; letting startNewSession() run
        // first would click "New Chat" and wipe that submitted conversation.
        // EXCEPTION: a FIRST turn of a new local chat must NOT land in the
        // currently-open remote conversation — the tool preamble would arrive
        // on top of an unrelated history and the model keeps its earlier
        // refusals. Start a genuinely fresh remote chat instead.
        if !isFirstTurn,
           let remote = await currentRemoteChat(bridge: bridge,
                                                config: config),
           SendSubmissionPolicy.urlHasChatID(remote.url) {
            let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: remote.url,
                vendor: config.vendor,
                chatID: remote.id
            ) ?? remote.url
            let reused = WebRemoteChatMapping(key: key,
                                              remoteChatID: remote.id,
                                              remoteURL: canonical,
                                              verifiedTitle: appState.selectedSession?.title)
            appState.saveWebRemoteChatMapping(reused)
            try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
            return reused
        }
        guard !freshSubmitPending,
              let newURL = try await driver.startNewSession(),
              SendSubmissionPolicy.urlHasChatID(newURL),
              let remoteID = WebRemoteChatIdentityLogic.chatIDFromURL(newURL),
              let remoteURL = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: newURL,
                vendor: config.vendor,
                chatID: remoteID
              ),
              let remoteHost = URL(string: remoteURL)?.host,
              remoteHost == providerHost else {
            // Fallback: the browser may already be on a valid chat page.
            // Use the current page state instead of blocking the send.
            if let remote = await currentRemoteChat(bridge: bridge,
                                                     config: config),
               SendSubmissionPolicy.urlHasChatID(remote.url) {
                let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                    baseURL: remote.url,
                    vendor: config.vendor,
                    chatID: remote.id
                ) ?? remote.url
                let mapping = WebRemoteChatMapping(key: key,
                                                    remoteChatID: remote.id,
                                                    remoteURL: canonical,
                                                    verifiedTitle: appState.selectedSession?.title)
                appState.saveWebRemoteChatMapping(mapping)
                try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
                return mapping
            }
            // Audit 2026-09-08: no mapping, no id, no new-chat URL change
            // (Kimi SPA keeps the shell URL until the first message lands).
            // Postpone binding: send first, capture the id afterwards.
            return nil
        }
        let mapping = WebRemoteChatMapping(key: key,
                                            remoteChatID: remoteID,
                                            remoteURL: remoteURL,
                                            verifiedTitle: appState.selectedSession?.title)
        appState.saveWebRemoteChatMapping(mapping)
        try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
        return mapping
    }

    /// Returns a refresh reason only for failures that can be fixed by a live
    /// model/effort catalog probe. Typed injection events are authoritative;
    /// generic errors use conservative keyword matching as a compatibility
    /// fallback for older driver implementations.
    private func webCatalogRefreshReason(for event: WebChatEvent) -> String? {
        switch event {
        case .modelInjectionFailed(let message), .effortInjectionFailed(let message):
            return message
        case .error(let message):
            let normalized = message.lowercased()
            let keywords = ["model", "effort", "injection", "not found in web ui", "not found in the web provider"]
            guard keywords.contains(where: { normalized.contains($0) }) else { return nil }
            return message
        default:
            return nil
        }
    }

    /// Refreshes the live model catalog once per provider/project/chat turn.
    /// Generic string errors use this bounded background refresh as a diagnostic
    /// fallback. Typed pre-send injection failures use the automatic one-shot
    /// retry path above, so no duplicate prompt is created.
    @MainActor
    private func scheduleWebCatalogRefreshIfNeeded(reason: String,
                                                    key: String,
                                                    config: WebProviderConfig,
                                                    projectID: String,
                                                    chatID: String,
                                                    assistantID: String) {
        guard !webCatalogRefreshKeys.contains(key) else { return }
        webCatalogRefreshKeys.insert(key)
        appendWebStatus(to: assistantID, line: "Model/effort injection failed: \(reason)\nRefreshing the live model catalog before your next retry…")
        Task { @MainActor in
            let result = await appState.refreshWebModelsAndEffort(for: config,
                                                                  projectID: projectID,
                                                                  chatID: chatID)
            let summary = [result.modelsMsg, result.effortMsg]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            appendWebStatus(to: assistantID,
                            line: summary.isEmpty ? "Model catalog refresh finished. Retry the message." : "Model catalog refresh finished: \(summary). Retry the message.")
        }
    }

    /// Appends a status line to the assistant bubble without ending the turn.
    @MainActor
    private func appendWebStatus(to assistantID: String, line: String) {
        messageStore.update(id: assistantID) { m in
            m.content = m.content.isEmpty ? line : "\(m.content)\n\(line)"
            m.isStreaming = false
        }
    }

    private func roleString(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    @MainActor
    private func finishWebTurn() {
        serveTimeoutTask?.cancel()
        serveTimeoutTask = nil
        appState.isLoading = false
        appState.isStreaming = false
        streamingText = ""
        currentAssistantMessageID = nil
        #if canImport(WebKit)
        activeWebProviderID = nil
        activeWebChatID = nil
        captchaSolverContext = nil
        #endif
    }

    private func buildACPMessages(text: String, files: [FileInfo], images: [ClipboardImage]) -> [ACPRequestMessage] {
        let message = ACPMessageBuilder.buildUserMessage(
            text: text,
            fileNames: files.map { $0.name },
            images: images.map { (mimeType: $0.mimeType, base64: $0.base64) }
        )
        return [message]
    }

    func submitQuestionAnswers(_ answers: [[String]]) {
        guard let pending = appState.pendingQuestionRequest,
              !pending.requestID.isEmpty else { return }
        let requestID = pending.requestID

        Task {
            do {
                try await appState.mimoClient.replyToQuestion(requestID: requestID, answers: answers)
                await MainActor.run {
                    appState.pendingQuestionRequest = nil
                    appState.isLoading = true
                    appState.isStreaming = true
                    if let assistantID = currentAssistantMessageID {
                        messageStore.update(id: assistantID) { msg in
                            msg.isStreaming = true
                            msg.isFinished = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    appState.isLoading = false
                    appState.isStreaming = false
                    if let assistantID = currentAssistantMessageID {
                        messageStore.update(id: assistantID) { msg in
                            msg.content = "Question reply failed: \(error.localizedDescription)"
                            msg.isStreaming = false
                            msg.isFinished = true
                        }
                    }
                }
            }
        }
    }

    func retryAssistantMessage(messageID: String) {
        guard let index = messageStore.messages.firstIndex(where: { $0.id == messageID }) else { return }
        for i in (0..<index).reversed() {
            if messageStore.messages[i].role == .user {
                resendMessage(messageStore.messages[i])
                return
            }
        }
    }
    
    @MainActor
    func handleSSEEvent(type: String, payload: [String: Any]) {
        guard let props = payload["properties"] as? [String: Any] else { return }
        let sessionID = props["sessionID"] as? String ?? ""
        
        // Events belong to the chat that started the turn, which may not be the
        // chat on screen while it streams in the background. Accept events for
        // the turn's session and for the visible one; drop everything else.
        let turnSessionID = messageStore.sessionID(owningMessageID: currentAssistantMessageID ?? "")
        guard sessionID == turnSessionID || sessionID == messageStore.currentSessionID else { return }
        
        switch type {
        case "question.asked":
            if let pending = PlanQuestionLogic.parseQuestionAskedEvent(properties: props) {
                appState.pendingQuestionRequest = pending
                pauseForPendingQuestion()
                if let assistantID = currentAssistantMessageID {
                    messageStore.update(id: assistantID) { msg in
                        msg.isStreaming = false
                        msg.isFinished = false
                    }
                }
            }

        case "question.replied", "question.rejected":
            if appState.pendingQuestionRequest?.sessionID == sessionID {
                appState.pendingQuestionRequest = nil
            }

        case "message.part.delta":
            let delta = props["delta"] as? String ?? ""
            let field = props["field"] as? String ?? ""
            
            if field == "text" && !delta.isEmpty {
                streamingText += delta
                messageStore.update(id: currentAssistantMessageID ?? "") { msg in
                    msg.content = streamingText
                }
            }
            
        case "message.part.updated":
            guard let part = props["part"] as? [String: Any],
                  let partType = part["type"] as? String else { break }

            messageStore.update(id: currentAssistantMessageID ?? "") { msg in
                if let parsed = PlanQuestionLogic.parseOpenCodeToolPart(part) {
                    PlanQuestionLogic.upsertToolCall(
                        &msg.parts,
                        name: parsed.toolName,
                        args: parsed.argsJSON,
                        result: parsed.result,
                        callID: parsed.callID
                    )
                    if PlanQuestionLogic.isQuestionTool(parsed.toolName), parsed.isPending, !parsed.questions.isEmpty {
                        msg.isStreaming = false
                        msg.isFinished = false
                        self.pauseForPendingQuestion()
                    }
                    self.syncExecutionSteps(from: msg.parts)
                    return
                }

                switch partType {
                case "text":
                    if let text = part["text"] as? String, !text.isEmpty {
                        streamingText = text
                        msg.content = text
                        MessageResponseMergeLogic.upsertTextPart(&msg.parts, text: text)
                    }
                case "reasoning":
                    if let text = part["text"] as? String, !text.isEmpty {
                        msg.reasoning = text
                        MessageResponseMergeLogic.upsertReasoningPart(&msg.parts, text: text)
                    }
                case "tool-invocation", "tool-call":
                    let toolName = part["toolName"] as? String ?? part["name"] as? String ?? "tool"
                    let input = part["input"] as? String ?? part["args"] as? String ?? part["arguments"] as? String ?? "{}"
                    let result = part["result"] as? String
                    PlanQuestionLogic.upsertToolCall(&msg.parts, name: toolName, args: input, result: result, callID: part["callID"] as? String ?? part["id"] as? String)
                    if PlanQuestionLogic.isQuestionTool(toolName), result == nil {
                        msg.isStreaming = false
                        msg.isFinished = false
                        self.pauseForPendingQuestion()
                    }
                    if toolName.lowercased() == "todowrite",
                       let steps = SessionPlanParser.steps(fromTodoWriteJSON: input) {
                        appState.currentSteps = steps
                        appState.showGoal = true
                    }
                case "step-start":
                    msg.parts.append(.stepStart)
                    appState.showGoal = true
                case "step-finish":
                    msg.parts.append(.stepFinish)
                default:
                    break
                }
                self.syncExecutionSteps(from: msg.parts)
            }
            
        case "session.status":
            if let status = props["status"] as? [String: String],
               status["type"] == "idle" {
                finishStreaming()
            }
            
        case "session.idle":
            finishStreaming()
            
            case "message.updated":
                if let info = props["info"] as? [String: Any],
                   let role = info["role"] as? String,
                   role == "assistant",
                   let messageID = info["id"] as? String {
                    let updateID = SessionSendLogic.assistantUpdateID(
                        localID: currentAssistantMessageID,
                        serverID: messageID
                    )
                    if let localID = currentAssistantMessageID, localID != messageID {
                        // Keep the local placeholder as the live update key and
                        // remember the server ID for DB reconciliation.
                        messageStore.update(id: localID) { msg in
                            msg.serverID = messageID
                            if msg.content.isEmpty {
                                msg.content = streamingText
                            }
                        }
                    }
                    currentAssistantMessageID = updateID
                    if let finish = info["finish"] as? String, finish == "stop" {
                        messageStore.setFinished(id: updateID)
                    }
                }
            
        default:
            break
        }
    }
    
    @MainActor
    private func pauseForPendingQuestion() {
        appState.isLoading = false
        appState.isStreaming = false
    }

    @MainActor
    private func syncExecutionSteps(from parts: [MessagePartContent]) {
        let synced = ExecutionStepSyncLogic.steps(from: parts, existing: appState.currentSteps)
        guard !synced.isEmpty else { return }
        appState.currentSteps = ExecutionStepSyncLogic.mergedSteps(existing: appState.currentSteps, incoming: synced)
        appState.showGoal = true
    }

    @MainActor
    private func finishStreaming() {
        let assistantID = currentAssistantMessageID ?? ""
        let turnSessionID = messageStore.sessionID(owningMessageID: assistantID)
            ?? appState.selectedSession?.id
        // A question pauses only its own chat. Another chat's question must not
        // keep this turn marked as streaming forever.
        guard appState.pendingQuestionRequest?.sessionID != turnSessionID else { return }
        serveTimeoutTask?.cancel()
        serveTimeoutTask = nil
        appState.isLoading = false
        appState.isStreaming = false
        sseClient.disconnect()

        let currentMessage = messageStore.message(id: assistantID)
        let hasToolActivity = currentMessage?.parts.contains { part in
            switch part {
            case .toolCall, .stepStart, .stepFinish:
                return true
            case .text, .reasoning, .image, .routeInfo, .compiledContext:
                return false
            }
        } ?? false
        let storedContent = currentMessage?.content
        let isThinkingPlaceholder = storedContent?.hasPrefix("Thinking…") == true
        let completedText: String? = streamingText.isEmpty
            ? (isThinkingPlaceholder ? nil : storedContent)
            : streamingText
        let isEmptyCompletion = ProviderResponseValidationLogic.shouldReportEmptyCompletion(
            text: completedText,
            reasoning: currentMessage?.reasoning,
            hasToolActivity: hasToolActivity
        )

        messageStore.setFinished(id: assistantID)
        if isEmptyCompletion {
            messageStore.update(id: assistantID) { msg in
                msg.content = ProviderResponseValidationLogic.emptyCompletionMessage
                msg.isFinished = true
                msg.isStreaming = false
            }
        } else if streamingText.isEmpty {
            messageStore.update(id: assistantID) { msg in
                if msg.content.isEmpty {
                    msg.content = L.t(AppLocalizationKey.locTaskCompletedMessage)
                }
            }
        }
        streamingText = ""
        currentAssistantMessageID = nil
        appState.scheduleGitRefresh(sessionID: turnSessionID)
    }

// MARK: - Draft persistence
    private func loadDraft(for sessionID: String?) {
        guard let sessionID = sessionID, !sessionID.isEmpty else {
            messageText = ""
            return
        }
        Task {
            do {
                let draft = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionID)
                await MainActor.run {
                    messageText = draft ?? ""
                }
            } catch {
                // Ignore draft load errors silently
            }
        }
    }
    
    private func saveDraft(_ text: String) {
        guard let sessionID = messageStore.currentSessionID, !sessionID.isEmpty else { return }
        Task {
            do {
                try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: text.isEmpty ? nil : text)
            } catch {
                // Ignore draft save errors silently
            }
        }
    }
    
    private func clearDraft() {
        guard let sessionID = messageStore.currentSessionID, !sessionID.isEmpty else { return }
        Task {
            do {
                try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: nil)
            } catch { }
        }
    }
}

/// Telegram-style floating button that jumps the chat back to the latest message.
struct ScrollToBottomButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.mimo.surface)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    Circle().stroke(Color.mimo.border.opacity(isHovering ? 0.9 : 0.5), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel("Scroll to latest message")
    }
}



/// Reports a chat message row's frame in the chat scroll space (used to
/// resolve the currently visible user message for the navigator).
struct ChatRowFrameReporter: ViewModifier {
    let rowID: String
    let isUser: Bool

    func body(content: Content) -> some View {
        if isUser {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChatRowFrameKey.self,
                        value: [rowID: geo.frame(in: .named(ChatScrollSpace.name))]
                    )
                }
            )
        } else {
            content
        }
    }
}

extension View {
    func chatRowFrameReporter(id: String, isUser: Bool) -> some View {
        modifier(ChatRowFrameReporter(rowID: id, isUser: isUser))
    }
}

/// Names the chat scroll coordinate space and reports the visible viewport
/// frame inside it.
struct ChatScrollSpaceReporter: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: ChatScrollSpace.name)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChatViewportFrameKey.self,
                        value: geo.frame(in: .named(ChatScrollSpace.name))
                    )
                }
            )
    }
}

extension View {
    func chatScrollSpaceReporter() -> some View {
        modifier(ChatScrollSpaceReporter())
    }
}
