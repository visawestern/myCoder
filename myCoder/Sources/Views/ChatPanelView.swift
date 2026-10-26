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

private struct PreparedLocalToolCall {
    let call: WebToolCall
    let callID: String
    let validationError: WebToolValidationError?
    let approval: PendingToolApproval?

    var argsSummary: String {
        call.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}

private struct AutoFreeNativeToolCall {
    let id: String
    let name: String
    let arguments: String

    var toolCall: MyCoderAutoFreeClient.Message.ToolCall {
        MyCoderAutoFreeClient.Message.ToolCall(
            id: id,
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }
}

struct ChatPanelView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var messageStore = MessageStore()
    @StateObject private var messageQueue = MessageQueue()
    @StateObject private var attachmentStore = MessageAttachmentStore()
    @State private var messageText = ""
    @State private var showFilePicker = false
    @State private var streamingText = ""
    @State private var currentAssistantMessageID: String?
    @State private var currentTask: Task<Void, Never>?
    @State private var previousSessionID: String?
    @State private var isChatBottomVisible = true
    @State private var userRowFrames: [String: CGRect] = [:]
    @State private var chatViewportFrame: CGRect = .zero
    @State private var currentUserMessageID: String?
    @State private var canLoadOlderMessages = false
    @State private var scrolledSessionID: String?
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
            if let notification = appState.transientProviderNotification {
                AutoFreeSwitchBanner(notification: notification) {
                    appState.transientProviderNotification = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }

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
                    let webView = appState.webView(for: webConfig,
                                                    projectID: panelConfig.projectID,
                                                    chatID: panelConfig.chatID)
                    WebProviderBrowserPanelRepresentable(webView: webView, config: panelConfig)
                        .frame(width: size.width, height: size.height)
                }
            }
            #endif

            if ChatPanelLayoutLogic.shouldUseCenteredInput(messageCount: messageStore.messages.count) {
                EmptyChatStateView(
                    messageText: $messageText,
                    attachmentStore: attachmentStore,
                    showFilePicker: $showFilePicker,
                    messageQueue: messageQueue,
                    onSend: sendMessage,
                    onStop: stopGeneration,
                    isLoading: appState.isLoading,
                    isLoadingChat: ChatLoadingIndicatorLogic.presentation(
                        isLoading: messageStore.isLoadingMessages,
                        messageCount: messageStore.messages.count
                    ) == .centered
                )
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
                                        Text(L.t(AppLocalizationKey.locLoadingChat))
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
                                        loadOlderMessages()
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .interfaceFont(size: 12, weight: .medium)
                                    .foregroundColor(Color.mimo.cyan)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .onAppear {
                                        guard canLoadOlderMessages else { return }
                                        loadOlderMessages()
                                    }
                                }
                                
                                ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
                                    if let separator = workedSeparator(before: index, in: displayMessages) {
                                        WorkedTimeSeparator(label: separator)
                                    }
                                    
                                    MessageRow(message: message, projectRoot: appState.toolWorkingDirectory)
                                        .id(message.id)
                                        .chatRowFrameReporter(id: message.id, isUser: message.role == .user)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(ChatScrollLogic.bottomAnchorID)
                                    .onAppear {
                                        isChatBottomVisible = true
                                        messageStore.isPinnedToBottom = true
                                    }
                                    .onDisappear {
                                        isChatBottomVisible = false
                                        messageStore.isPinnedToBottom = false
                                    }
                            }.padding(.vertical, 16)
                        }
                        .chatScrollSpaceReporter()
                        .onPreferenceChange(ChatRowFrameKey.self) { value in
                            userRowFrames = value
                        }
                        .onPreferenceChange(ChatViewportFrameKey.self) { value in
                            chatViewportFrame = value
                        }
                        .onChange(of: userRowFrames) { _ in updateCurrentVisibleUserMessage() }
                        .onChange(of: chatViewportFrame) { _ in updateCurrentVisibleUserMessage() }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            updateCurrentVisibleUserMessage()
                        }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            guard ChatScrollLogic.shouldAutoScroll(wasAtBottom: isChatBottomVisible) else {
                                return
                            }
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: messageStore.currentSessionID) { newID in
                            guard ChatScrollLogic.shouldScrollOnSessionChange(
                                oldSessionID: scrolledSessionID,
                                newSessionID: newID
                            ) else { return }
                            scrolledSessionID = newID
                            DispatchQueue.main.async {
                                proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
                            }
                            // Load draft for new session
                            loadDraft(for: newID)
                        }
                        .onChange(of: messageText) { newText in
                            // Debounced draft save
                            draftSaveTask?.cancel()
                            draftSaveTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    saveDraft(newText)
                                }
                            }
                        }
                        .onAppear {
                            guard ChatScrollLogic.shouldScrollOnSessionChange(
                                oldSessionID: scrolledSessionID,
                                newSessionID: messageStore.currentSessionID
                            ) else { return }
                            scrolledSessionID = messageStore.currentSessionID
                            DispatchQueue.main.async {
                                proxy.scrollTo(ChatScrollLogic.bottomAnchorID, anchor: .bottom)
                            }
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
                        .animation(.easeOut(duration: 0.15), value: isChatBottomVisible)
                    }

                    ComposerAttachmentPreview(store: attachmentStore)

                    if let pending = appState.pendingQuestionRequest {
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
                        isLoading: appState.isLoading,
                        attachmentStore: attachmentStore,
                        showFilePicker: $showFilePicker,
                        messageQueue: messageQueue,
                        contextUsage: currentContextUsage
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
                    let webView = appState.webView(for: webConfig,
                                                    projectID: panelConfig.projectID,
                                                    chatID: panelConfig.chatID)
                    WebProviderBrowserPanelRepresentable(webView: webView, config: panelConfig)
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
            if let sessionID = newSessionID {
                guard SessionReloadLogic.shouldReloadMessages(
                    newSessionID: sessionID,
                    currentSessionID: messageStore.currentSessionID,
                    localMessageCount: messageStore.messages.count,
                    isLoading: appState.isLoading
                ) else { return }
                loadSessionMessages(sessionID: sessionID)
                #if canImport(WebKit)
                // User directive 2026-09-09: moving to another chat/project
                // surfaces THAT chat's pooled webview ("another tab of the
                // same site") when one exists; otherwise the panel keeps
                // showing whatever it showed.
                let projectID = appState.selectedWorkspace?.id
                    ?? appState.selectedWorkspace?.path ?? "global"
                appState.showPanelForChatIfPooled(projectID: projectID, chatID: sessionID)
                #endif
            } else {
                messageStore.clear()
                messageText = ""
                attachmentStore.clear()
            }
        }
        .onChange(of: appState.isLoading) { loading in
            if !loading {
                messageQueue.processNext()
                flushPendingSpecNodePrompt()
            }
        }
        .onChange(of: appState.pendingSpecNodePrompt?.id) { _ in
            flushPendingSpecNodePrompt()
        }
        .onChange(of: messageStore.loadedSessionID) { sessionID in
            if let sessionID {
                reattachPendingApprovals(sessionID: sessionID)
            }
            flushPendingSpecNodePrompt()
        }
        .onChange(of: messageStore.loadingSessionID) { _ in
            flushPendingSpecNodePrompt()
        }
        .onAppear {
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
                        agentModeOverride: queued.type.toAgentMode
                    )
                }
            }
            if let sessionID = appState.selectedSession?.id {
                previousSessionID = sessionID
                loadSessionMessages(sessionID: sessionID)
            }
            flushPendingSpecNodePrompt()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editMessage)) { notification in
            guard let messageID = notification.userInfo?["messageId"] as? String,
                  let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
            loadMessageIntoComposer(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resendMessage)) { notification in
            guard let messageID = notification.userInfo?["messageId"] as? String,
                  let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
            resendMessage(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .retryMessage)) { notification in
            guard let messageID = notification.userInfo?["messageId"] as? String else { return }
            retryAssistantMessage(messageID: messageID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopGeneration)) { _ in
            stopGeneration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiSendRequested)) { notification in
            guard let message = notification.userInfo?["message"] as? String, !message.isEmpty else { return }
            if let chatId = notification.userInfo?["chatId"] as? String, !chatId.isEmpty {
                messageStore.currentSessionID = chatId
            }
            messageText = message
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .submitPlanQuestionAnswers)) { notification in
            guard let answers = notification.userInfo?["answers"] as? [[String]] else { return }
            submitQuestionAnswers(answers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localToolApprovalResolved)) { notification in
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
        .onReceive(NotificationCenter.default.publisher(for: .webToolApprovalResolved)) { notification in
            guard let approvalID = notification.userInfo?["approvalID"] as? String,
                  let approved = notification.userInfo?["approved"] as? Bool else { return }
            activeApprovalBox?.resolve(id: approvalID, approved: approved)
            // Clear the card from the assistant message: the driver resumes
            // with the verdict and the turn continues.
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
        .onReceive(NotificationCenter.default.publisher(for: .copyEntireChat)) { _ in
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
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let name = url.lastPathComponent
                    let ext = url.pathExtension
                    let type = FileType.from(ext: ext)
                    let path = url.path
                    attachmentStore.appendFile(FileInfo(name: name, type: type, path: path))
                }
            }
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
            messageStore.clear()
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
            // Route the session to its project database BEFORE any read or
            // write. The in-memory route map is rebuilt on every launch, so a
            // chat opened outside its project's own sidebar (recent chats,
            // grid view) used to look like a global session: its history was
            // read from the global database and its new messages were written
            // there, splitting the conversation across two stores.
            let sessionDirectory = appState.sessions.first(where: { $0.id == sessionID })?.directory
                ?? appState.selectedSession?.directory
            if let sessionDirectory, !sessionDirectory.isEmpty {
                DatabaseBridge.shared.registerSessionProjectIfKnown(
                    sessionID: sessionID,
                    projectPath: sessionDirectory
                )
            }
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
                                    error: String) {
        let preparedSessionID: String?
        if messageStore.currentSessionID == nil {
            preparedSessionID = appState.prepareLocalSessionForSend(title: text)
            messageStore.currentSessionID = preparedSessionID
        } else {
            preparedSessionID = messageStore.currentSessionID
        }
        let userMessage = Message(
            role: .user,
            content: text,
            files: files.isEmpty ? nil : files,
            parts: MessagePartsBuilder.displayParts(text: text, images: images)
        )
        messageStore.append(userMessage)
        messageStore.append(Message(role: .assistant, content: error, isFinished: true))
        if let preparedSessionID,
           let preparedSession = appState.sessions.first(where: { $0.id == preparedSessionID }) {
            appState.selectedSession = preparedSession
        }
    }

    @MainActor
    private func prepareSessionBeforeAppending(route: SendRoute, title: String) async -> String? {
        if let existing = messageStore.currentSessionID {
            return existing
        }
        if let selected = appState.selectedSession?.id {
            messageStore.currentSessionID = selected
            return selected
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
                messageStore.currentSessionID = remote.id
                return remote.id
            } catch {
                return nil
            }
        }

        let localID = appState.prepareLocalSessionForSend(title: title)
        messageStore.currentSessionID = localID
        return localID
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
        if let error = SendReadinessLogic.connectionValidationError(
            serverConnected: appState.serverConnected,
            selectedProviderID: appState.selectedProviderID,
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
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
            return
        }
        
        let text = messageText
        let files = attachmentStore.attachedFiles
        let images = attachmentStore.attachedImages
        messageText = ""
        clearDraft()
        attachmentStore.clear()
        
        if appState.isLoading {
            messageQueue.enqueue(
                text: text,
                files: files,
                images: images,
                type: MessageType(from: appState.agentMode)
            )
            return
        }
        
        currentTask = Task {
            await sendDirectly(text: text, files: files, images: images)
        }
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
        case .openAICompatible, .autoFree: return true
        default: return false
        }
    }

    private var selectedContextLimit: Int {
        let model = appState.effectiveSelectedModel()
        var reported: Int?
        if appState.selectedProviderID == MyCoderAutoFreeProvider.builtInID {
            reported = MyCoderAutoFreeStore.shared.provider.models
                .first(where: { $0.id == model })?.contextLength
        }
        return ContextWindowCatalog.limit(for: model, reported: reported)
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
        case .autoFree:
            return { prompt in
                let store = MyCoderAutoFreeStore.shared
                store.syncModel(self.appState.effectiveSelectedModel())
                let context = OpenCodeRequestContext(
                    sessionID: OpenCodeRequestContext.sessionID(
                        from: self.messageStore.currentSessionID ?? self.appState.selectedSession?.id ?? ""
                    ),
                    projectID: OpenCodeRequestContext.projectID(fromPath: self.appState.selectedWorkspace?.path ?? "")
                )
                var content = ""
                for try await event in store.streamChat(
                    messages: [MyCoderAutoFreeClient.Message(role: "user", content: prompt)],
                    context: context,
                    tools: MyCoderAutoFreeClient.gateToolDefinitions(),
                    toolChoice: "none"
                ) {
                    if case .content(let chunk) = event { content += chunk }
                }
                return content
            }
        default:
            return { _ in throw ConversationSummarizerError.nothingToCompact }
        }
    }

    /// Replace the model-bound history with a factual summary message. The
    /// full chat stays visible; `historyForModel` cuts at the newest summary.
    @MainActor
    private func compactConversation(reason: String) async {
        guard !isCompacting else { return }
        let history = ConversationCompactionLogic.historyForModel(messageStore.messages)
        guard ConversationCompactionLogic.plan(messages: history) != nil else {
            messageStore.append(Message(
                role: .assistant,
                content: ConversationSummarizerError.nothingToCompact.errorDescription ?? "Nothing to compact.",
                isFinished: true
            ))
            return
        }
        let route = currentRoute()
        guard supportsLocalHistoryCompaction(route) else {
            messageStore.append(Message(
                role: .assistant,
                content: "Compaction is not available for this provider: its history is kept on the server (mimo/opencode serve, web or ACP), so a local summary would not shrink it.",
                isFinished: true
            ))
            return
        }
        isCompacting = true
        defer { isCompacting = false }

        let beforeTokens = ContextUsageLogic.usedTokens(messages: history)
        let summarizer = ConversationSummarizer(transport: summaryTransport(for: route))
        do {
            let summary = try await summarizer.summarize(messages: history)
            messageStore.append(ConversationCompactionLogic.summaryMessage(summary: summary))
            let afterTokens = ContextUsageLogic.estimateTokens(summary)
            messageStore.append(Message(
                role: .assistant,
                content: "Context compacted (\(reason)): \(history.count) messages summarized, ~\(ContextUsageLogic.formatTokens(beforeTokens)) → ~\(ContextUsageLogic.formatTokens(afterTokens)) tokens. The full chat stays visible; the model now continues from the summary.",
                isFinished: true
            ))
        } catch {
            messageStore.append(Message(
                role: .assistant,
                content: "Context compaction failed: \(error.localizedDescription)",
                isFinished: true
            ))
        }
    }

    /// Auto-compaction trigger (plan: 90% of the window). Runs before the
    /// outgoing history is built; failures never block the send.
    @MainActor
    private func autoCompactIfNeeded(route: SendRoute) async {
        guard supportsLocalHistoryCompaction(route) else { return }
        let history = ConversationCompactionLogic.historyForModel(messageStore.messages)
        guard !history.isEmpty else { return }
        let usage = ContextUsageLogic.usage(messages: history, limitTokens: selectedContextLimit)
        guard ContextUsageLogic.shouldCompact(usage) else { return }
        await compactConversation(reason: "auto at \(usage.percent)%")
    }

    func sendDirectly(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage] = [],
        agentModeOverride: AgentMode? = nil,
        retryCount: Int = 0,
        retryPlan: SessionBusyRetryLogic.RetryPlan? = nil
    ) async {
        if let error = SendReadinessLogic.connectionValidationError(
            serverConnected: appState.serverConnected,
            selectedProviderID: appState.selectedProviderID,
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected
        ) {
            await MainActor.run {
                self.recordRejectedSend(text: text, files: files, images: images, error: error)
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
                self.recordRejectedSend(text: text, files: files, images: images, error: error)
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
        // Auto-compact BEFORE any history is assembled for this turn (plan:
        // 90% of the model window). A failed summary is reported in-chat by
        // compactConversation and the send proceeds with the full history.
        await autoCompactIfNeeded(route: route)
        // A/B: host-side project auto-search. Gather files matching the request
        // from the stored index and prepend them to the MODEL-BOUND text only;
        // the displayed bubble keeps the raw user text. A missing/stale index
        // simply yields no block (never blocks the send).
        let autoContextRecords = appState.selectedWorkspace.map {
            ProjectFileIndexStore.load(projectPath: $0.path)
        } ?? []
        let autoContextBlock = ProjectContextGatherLogic.block(query: text, records: autoContextRecords)
        let modelText = autoContextBlock.isEmpty ? text : autoContextBlock + "\n\n" + text
        let preparedSessionID: String?
        if let retryPlan {
            preparedSessionID = retryPlan.sessionID
            await MainActor.run { messageStore.currentSessionID = retryPlan.sessionID }
        } else {
            preparedSessionID = await prepareSessionBeforeAppending(route: route, title: text)
        }
        let userMessage = Message(
            role: .user,
            content: text,
            files: files.isEmpty ? nil : files,
            parts: MessagePartsBuilder.displayParts(text: text, images: images)
        )
        await MainActor.run {
            if retryPlan == nil {
                messageStore.append(userMessage)
            }
            if let preparedSessionID,
               let preparedSession = appState.sessions.first(where: { $0.id == preparedSessionID }) {
                appState.selectedSession = preparedSession
            }
        }
        let parts = MessagePartsBuilder.build(text: modelText, files: files, images: images)
        await MainActor.run {
            currentAssistantMessageID = assistantID
            if retryPlan == nil {
                messageStore.append(Message(id: assistantID, role: .assistant, content: "", isStreaming: true))
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
                let chatKey = preparedSessionID ?? assistantID
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
                        let result = try await OpenCodeServeClient.send(
                            baseURL: baseURL, headers: headers, modelID: model,
                            text: modelText, providerID: providerID, sessionID: sid
                        )
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
                    let msgs = messageStore.messages
                    let modelHistory = ConversationCompactionLogic.historyForModel(msgs)
                    let history = modelHistory.count >= 2 ? Array(modelHistory.dropLast(2)) : []
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
                let projectRoot = appState.toolWorkingDirectory
                let sysPrompt = WebToolProtocolEmulator.systemPreamble(
                    userSystemPrompt: params.systemPrompt ?? "",
                    projectRoot: projectRoot,
                    isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil
                )
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
                // Auto Free path: each tool block is executed locally against
                // the selected project, and its result is fed back so the
                // model can continue instead of stopping at a raw ```tool block.
                var executor = ProjectWebToolExecutor(
                    projectRoot: projectRoot,
                    accessLevel: appState.accessLevel
                )
                executor.subagentLauncher = subagentLauncher(
                    projectRoot: projectRoot,
                    transport: .openAICompatible(baseURL: URL(string: baseURL) ?? URL(fileURLWithPath: "/"), apiKey: apiKey ?? "", model: model)
                )
                let maxIterations = 15
                var conversation = msgs
                var finalText = ""
                var finalUsage: UsageCapture? = nil
                var toolParts: [MessagePartContent] = []
                do {
                    for iteration in 0..<maxIterations {
                        let result = try await DirectChatClient.send(
                            baseURL: baseURL, apiKey: apiKey, model: model,
                            messages: conversation, parameters: params
                        )
                        let response = result.content
                        finalUsage = result.usage
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
                        let prepared = prepareLocalToolCalls(
                            calls,
                            modelContext: response,
                            projectRoot: projectRoot,
                            accessLevel: appState.accessLevel
                        )
                        for item in prepared {
                            toolParts.append(.toolCall(
                                name: item.call.name,
                                args: item.argsSummary,
                                result: item.validationError.map { "validation error: \($0)" },
                                callID: item.callID
                            ))
                        }
                        publishToolParts(toolParts, assistantID: assistantID)
                        enqueueLocalToolApprovals(
                            prepared.compactMap(\.approval),
                            assistantID: assistantID
                        )

                        var resultsBlock = ""
                        for item in prepared {
                            guard !Task.isCancelled else { break }
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
                                            result: "validation error: \(error)"
                                        ) + "\n"
                                        continue
                                    }
                                case .denied(let message):
                                    resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                        name: item.call.name, result: message
                                    ) + "\n"
                                    toolParts = localToolParts(
                                        toolParts,
                                        settingResult: message,
                                        callID: item.callID
                                    )
                                    publishToolParts(toolParts, assistantID: assistantID)
                                    continue
                                case .notApplicable:
                                    resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                        name: item.call.name,
                                        result: "validation error: \(validationError)"
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
                                    toolParts = localToolParts(
                                        toolParts,
                                        settingResult: denial,
                                        callID: item.callID
                                    )
                                    publishToolParts(toolParts, assistantID: assistantID)
                                    continue
                                }
                            }
                            let toolResult = await executor.execute(item.call, userApproved: true)
                            guard !Task.isCancelled else { break }
                            resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                name: item.call.name, result: toolResult
                            ) + "\n"
                            toolParts = localToolParts(
                                toolParts,
                                settingResult: toolResult,
                                callID: item.callID
                            )
                            publishToolParts(toolParts, assistantID: assistantID)
                        }
                        conversation.append(DirectChatMessage(role: "assistant", content: response))
                        conversation.append(DirectChatMessage(role: "user", content: resultsBlock))
                        finalText = response
                        await MainActor.run {
                            self.messageStore.update(id: assistantID) { msg in
                                msg.content = response + "\n\n⏳ Running tools..."
                                msg.parts = toolParts
                                msg.isStreaming = true
                            }
                        }
                    }
                    await MainActor.run {
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        self.streamingText = ""
                        self.messageStore.update(id: assistantID) { msg in
                            msg.content = finalText
                            msg.usage = finalUsage
                            msg.parts = toolParts
                            msg.isFinished = true
                            msg.isStreaming = false
                        }
                        self.currentAssistantMessageID = nil
                    }
                } catch {
                    await MainActor.run {
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        self.messageStore.update(id: assistantID) { msg in
                            msg.content = "Local model error: \(error.localizedDescription)"
                            msg.isFinished = true
                            msg.isStreaming = false
                        }
                        self.currentAssistantMessageID = nil
                    }
                }
                return
            }

            // ── Built-in myCoder Auto Free provider branch (direct API) ─
            if case .autoFree = route {
                let store = MyCoderAutoFreeStore.shared
                let model = appState.effectiveSelectedModel()
                await MainActor.run { store.syncModel(model) }
                let priorTurns = await MainActor.run { () -> [MyCoderAutoFreeHistoryLogic.Turn] in
                    let modelHistory = ConversationCompactionLogic.historyForModel(messageStore.messages)
                    let priorMessages = modelHistory.count >= 2
                        ? Array(modelHistory.dropLast(2))
                        : []
                    return priorMessages.map {
                        MyCoderAutoFreeHistoryLogic.Turn(
                            role: roleString($0.role),
                            content: $0.content,
                            isFinished: $0.isFinished
                        )
                    }
                }
                let history = MyCoderAutoFreeHistoryLogic.history(from: priorTurns)
                let autoFreePayload = autoFreeMessageParts(text: modelText, files: files, images: images)
                var conversationMessages: [MyCoderAutoFreeClient.Message] = history.map {
                    MyCoderAutoFreeClient.Message(role: $0.role, content: $0.content)
                }
                conversationMessages.append(MyCoderAutoFreeClient.Message(
                    role: "user",
                    parts: autoFreePayload.parts
                ))
                let attachmentNotice = autoFreePayload.warnings.joined(separator: "\n")
                let projectRoot = appState.toolWorkingDirectory
                let autoFreeContext = OpenCodeRequestContext(
                    sessionID: OpenCodeRequestContext.sessionID(
                        from: messageStore.currentSessionID ?? appState.selectedSession?.id ?? ""
                    ),
                    projectID: OpenCodeRequestContext.projectID(fromPath: projectRoot)
                )
                var executor = ProjectWebToolExecutor(
                    projectRoot: projectRoot,
                    accessLevel: appState.accessLevel
                )
                executor.subagentLauncher = subagentLauncher(
                    projectRoot: projectRoot,
                    transport: .autoFree
                )
                let maxIterations = 15
                var streamedContent = ""
                var streamedReasoningSegments: [String] = []
                var allToolCallParts: [MessagePartContent] = []
                do {
                    for iteration in 0..<maxIterations {
                        var response = ""
                        var iterationReasoning = ""
                        var nativeCalls: [AutoFreeNativeToolCall] = []
                        for try await event in store.streamChat(
                            messages: conversationMessages,
                            projectRoot: projectRoot,
                            isGitRepo: (try? GitRepository.repositoryRoot(for: projectRoot)) != nil,
                            context: autoFreeContext
                        ) {
                            let e: StreamEvent = event
                            switch e {
                            case .content(let text):
                                response += text
                            case .reasoning(let text):
                                iterationReasoning += text
                            case .toolCall(let id, let name, let arguments):
                                nativeCalls.append(AutoFreeNativeToolCall(id: id, name: name, arguments: arguments))
                            }
                            let display = [attachmentNotice, response].filter { !$0.isEmpty }.joined(separator: "\n\n")
                            let currentSegments = streamedReasoningSegments + (iterationReasoning.isEmpty ? [] : [iterationReasoning])
                            let currentParts = allToolCallParts + (iterationReasoning.isEmpty ? [] : [MessagePartContent.reasoning(iterationReasoning)])
                            await MainActor.run {
                                self.messageStore.update(id: assistantID) { m in
                                    m.content = display
                                    m.reasoning = currentSegments.joined(separator: "\n\n")
                                    m.parts = currentParts
                                    m.isStreaming = true
                                }
                            }
                        }
                        // Accumulate reasoning across iterations
                        if !iterationReasoning.isEmpty {
                            streamedReasoningSegments.append(iterationReasoning)
                            allToolCallParts.append(.reasoning(iterationReasoning))
                        }
                        let nativeWebCalls: [(id: String, call: WebToolCall)] = nativeCalls.compactMap { native in
                            guard let call = MyCoderAutoFreeClient.emulatedToolCall(
                                name: native.name,
                                arguments: native.arguments
                            ) else { return nil }
                            return (native.id, call)
                        }
                        let calls = nativeWebCalls.map(\.call)
                            + WebToolProtocolEmulator.parseToolCalls(from: response)
                        if calls.isEmpty || WebToolProtocolEmulator.shouldStopLoop(iteration: iteration, maxIterations: maxIterations, lastResponse: response) {
                            if calls.isEmpty, let feedback = WebToolProtocolEmulator.malformedToolBlockFeedback(from: response) {
                                conversationMessages.append(MyCoderAutoFreeClient.Message(role: "assistant", content: response))
                                conversationMessages.append(MyCoderAutoFreeClient.Message(role: "user", content: feedback))
                                continue
                            }
                            streamedContent = response
                            break
                        }
                        let prepared = prepareLocalToolCalls(
                            calls,
                            modelContext: response,
                            projectRoot: projectRoot,
                            accessLevel: appState.accessLevel
                        )
                        for item in prepared {
                            allToolCallParts.append(.toolCall(
                                name: item.call.name,
                                args: item.argsSummary,
                                result: item.validationError.map { "validation error: \($0)" },
                                callID: item.callID
                            ))
                        }
                        publishToolParts(allToolCallParts, assistantID: assistantID)
                        enqueueLocalToolApprovals(
                            prepared.compactMap(\.approval),
                            assistantID: assistantID
                        )

                        var resultsBlock = ""
                        var nativeResults: [String: String] = [:]
                        for (index, item) in prepared.enumerated() {
                            guard !Task.isCancelled else { break }
                            let nativeID = index < nativeWebCalls.count ? nativeWebCalls[index].id : nil
                            if let validationError = item.validationError {
                                switch await resolveOutOfProjectAccess(item, assistantID: assistantID) {
                                case .allowed(let grantedRoots):
                                    if let error = WebToolProtocolEmulator.validate(
                                        item.call,
                                        projectRoot: projectRoot,
                                        accessLevel: appState.accessLevel,
                                        grantedRoots: grantedRoots
                                    ) {
                                        let text = "validation error: \(error)"
                                        if let nativeID {
                                            nativeResults[nativeID] = text
                                        } else {
                                            resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                                name: item.call.name,
                                                result: text
                                            ) + "\n"
                                        }
                                        continue
                                    }
                                case .denied(let message):
                                    if let nativeID {
                                        nativeResults[nativeID] = message
                                    } else {
                                        resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                            name: item.call.name, result: message
                                        ) + "\n"
                                    }
                                    allToolCallParts = localToolParts(
                                        allToolCallParts,
                                        settingResult: message,
                                        callID: item.callID
                                    )
                                    publishToolParts(allToolCallParts, assistantID: assistantID)
                                    continue
                                case .notApplicable:
                                    let text = "validation error: \(validationError)"
                                    if let nativeID {
                                        nativeResults[nativeID] = text
                                    } else {
                                        resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                            name: item.call.name,
                                            result: text
                                        ) + "\n"
                                    }
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
                                    if let nativeID {
                                        nativeResults[nativeID] = denial
                                    } else {
                                        resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                            name: item.call.name, result: denial
                                        ) + "\n"
                                    }
                                    allToolCallParts = localToolParts(
                                        allToolCallParts,
                                        settingResult: denial,
                                        callID: item.callID
                                    )
                                    publishToolParts(allToolCallParts, assistantID: assistantID)
                                    continue
                                }
                            }
                            let result = await executor.execute(item.call, userApproved: true)
                            guard !Task.isCancelled else { break }
                            if let nativeID {
                                nativeResults[nativeID] = result
                            } else {
                                resultsBlock += WebToolProtocolEmulator.formatToolResult(
                                    name: item.call.name, result: result
                                ) + "\n"
                            }
                            allToolCallParts = localToolParts(
                                allToolCallParts,
                                settingResult: result,
                                callID: item.callID
                            )
                            publishToolParts(allToolCallParts, assistantID: assistantID)
                        }
                        if nativeCalls.isEmpty {
                            conversationMessages.append(MyCoderAutoFreeClient.Message(role: "assistant", content: response))
                            conversationMessages.append(MyCoderAutoFreeClient.Message(role: "user", content: resultsBlock))
                        } else {
                            conversationMessages.append(MyCoderAutoFreeClient.Message(
                                role: "assistant",
                                content: response,
                                toolCalls: nativeCalls.map { $0.toolCall }
                            ))
                            for native in nativeCalls {
                                conversationMessages.append(MyCoderAutoFreeClient.Message(
                                    role: "tool",
                                    content: nativeResults[native.id] ?? "",
                                    toolCallID: native.id
                                ))
                            }
                            if !resultsBlock.isEmpty {
                                conversationMessages.append(MyCoderAutoFreeClient.Message(role: "user", content: resultsBlock))
                            }
                        }
                        streamedContent = response
                        // Add tool call parts to message for UI spoilers
                        await MainActor.run {
                            self.messageStore.update(id: assistantID) { m in
                                m.content = [attachmentNotice, response, "\n\n⏳ Running tools..."].filter { !$0.isEmpty }.joined(separator: "\n\n")
                                m.reasoning = streamedReasoningSegments.joined(separator: "\n\n")
                                m.parts = allToolCallParts
                                m.isStreaming = true
                            }
                        }
                    }
                    let finalDisplay = [attachmentNotice, streamedContent].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    await MainActor.run {
                        self.messageStore.update(id: assistantID) { m in
                            m.content = finalDisplay
                            m.reasoning = streamedReasoningSegments.joined(separator: "\n\n")
                            m.parts = allToolCallParts
                            m.isFinished = true
                            m.isStreaming = false
                        }
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
                        self.currentAssistantMessageID = nil
                    }
                } catch {
                    await MainActor.run {
                        self.messageStore.update(id: assistantID) { m in
                            m.content = "myCoder Auto Free error: \(error.localizedDescription)"
                            m.isFinished = true
                            m.isStreaming = false
                        }
                        self.appState.isLoading = false
                        self.appState.isStreaming = false
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
                let chatID = messageStore.currentSessionID ?? appState.selectedSession?.id ?? assistantID
                activeWebChatID = chatID
                await runWebChatTurn(config: cfg, text: modelText, assistantID: assistantID, chatID: chatID)
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
                let response = try await acpClient.sendChatCompletion(
                    messages: acpMessages,
                    model: appState.selectedModel,
                    agent: acpAgent,
                    variant: acpVariant,
                    parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel()),
                    stream: false
                )

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
            guard let sessionID = messageStore.currentSessionID
                    ?? appState.selectedSession?.id
                    ?? selectedID else {
                throw MimoServeError.httpError(statusCode: 0)
            }

            await MainActor.run { messageStore.currentSessionID = sessionID }
            
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
                let hasPendingQuestion = self.appState.pendingQuestionRequest != nil
                let mergedParts = messageStore.messages.first(where: { $0.id == self.currentAssistantMessageID })?.parts ?? []
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
                        existing: messageStore.messages.first(where: { $0.id == self.currentAssistantMessageID }) ?? Message(role: .assistant, content: ""),
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
                    self.refreshGitForCurrentSession()
                    // Notify: task complete
                    if let session = self.appState.selectedSession {
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
                if let sessionID = messageStore.currentSessionID ?? selectedID,
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
                self.refreshGitForCurrentSession()
            }
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

    private func refreshGitForCurrentSession() {
        appState.scheduleGitRefresh(sessionID: messageStore.currentSessionID)
    }
    
    /// One assistant message can have several gated calls. They are all
    /// registered and rendered before the loop starts awaiting them, so the
    /// user sees the full queue instead of one modal at a time.

    private func subagentLauncher(
        projectRoot: String,
        transport: SubagentRunner.Transport
    ) -> (String, String) async -> String {
        let parentSessionID = messageStore.currentSessionID ?? appState.selectedSession?.id ?? ""
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
        accessLevel: AccessLevel
    ) -> [PreparedLocalToolCall] {
        calls.map { call in
            let callID = UUID().uuidString
            var validationError = WebToolProtocolEmulator.validate(
                call, projectRoot: projectRoot, accessLevel: accessLevel
            )
            if call.arguments["__mycoder_truncated"] == "1", validationError == nil {
                validationError = .incompleteJSON
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
                approval: approval
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
                action: sessionID.isEmpty ? nil : .openSession(sessionID)
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
        currentTask?.cancel()
        currentTask = nil
        // A direct-model turn may be suspended on queued approvals. Deny
        // only this chat's queue; approvals in other chats keep waiting.
        if let sessionID = messageStore.currentSessionID ?? appState.selectedSession?.id {
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
        messageQueue.cancelAll()

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

        if let sessionID = messageStore.currentSessionID {
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
        refreshGitForCurrentSession()
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

    func loadOlderMessages() {
        guard let sessionID = messageStore.currentSessionID else { return }
        guard !messageStore.isLoadingOlder else { return }  // Prevent cascade

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
                type: MessageType(from: appState.agentMode)
            )
            return
        }

        Task {
            await sendDirectly(text: draft.text, files: draft.files, images: draft.images)
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
                                chatID: String) async {
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

        // Each project/chat/provider gets an isolated hidden WKWebView page;
        // the shared cookie store keeps login state without mixing conversations.
        let projectID = appState.selectedWorkspace?.id ?? appState.selectedWorkspace?.path ?? "global"
        let refreshKey = "\(effectiveConfig.id)|\(projectID)|\(chatID)"
        webCatalogRefreshKeys.remove(refreshKey)
        let webView = appState.webView(for: effectiveConfig, projectID: projectID, chatID: chatID)
        // User directive 2026-09-09: surface this provider's live page in the
        // in-chat mini browser BEFORE the turn runs, so the user watches the
        // actual load/typing/answer instead of a hidden offscreen window.
        appState.showWebBrowserPanel(for: effectiveConfig, projectID: projectID, chatID: chatID)
        // Resolve vendor-specific selectors from the catalog.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: effectiveConfig.vendor.id)
        let selectors = WebVendorSelectors(
            input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
            sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='end'], button[data-testid='send-button'], .send-button-container",
            responseContainer: catalogEntry?.responseContainer ?? "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: catalogEntry?.stopButton ?? ".send-button-container.stop, button[aria-label*='top'], button[data-testid='stop-button'], button[class*='stop']"
        )
        let bridge = WKWebViewBrowserBridge(webView: webView, selectors: selectors)

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
            let currentURL = webView.url?.absoluteString ?? ""
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
                    let reloadURL = webView.url?.absoluteString ?? effectiveConfig.chatURL
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
        let smartSendIsFirstTurn = appState.webSessionIsFirstTurn(appState.webRemoteChatKey(
            for: effectiveConfig, projectID: projectID, chatID: chatID
        ))
        var smartSendMessage = text
        if smartSendIsFirstTurn {
            let preamble = WebToolProtocolEmulator.systemPreamble(
                userSystemPrompt: effectiveConfig.systemPrompt,
                projectRoot: smartSendWorkspacePath,
                directory: smartSendWorkspacePath,
                isGitRepo: (try? GitRepository.repositoryRoot(for: smartSendWorkspacePath)) != nil
            )
            smartSendMessage = preamble + "\n\n---\n\n" + text
        }
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
                                   approvalBox: approvalBox)

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
                        self.captchaSolverContext = WebCaptchaSolverContext(webView: webView, note: note)
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
                                                accessLevel: appState.accessLevel)
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
    private func currentRemoteChat(bridge: WKWebViewBrowserBridge,
                                   config: WebProviderConfig) async -> (id: String, url: String)? {
        guard let currentURL = try? await bridge.currentURL(),
              let host = URL(string: currentURL)?.host,
              host == URL(string: config.chatURL)?.host,
              let id = WebRemoteChatIdentityLogic.chatIDFromURL(currentURL),
              !id.isEmpty else { return nil }
        return (id, currentURL)
    }

    private func bindWebRemoteChat(driver: WebChatDriver,
                                   bridge: WKWebViewBrowserBridge,
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

    private func autoFreeMessageParts(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage]
    ) -> (parts: [MyCoderAutoFreeContentPart], warnings: [String]) {
        var imageDataURLs = images.compactMap { (image: ClipboardImage) -> String? in
            guard !image.base64.isEmpty else { return nil }
            return MessagePartsBuilder.dataURL(mimeType: image.mimeType, base64: image.base64)
        }
        var textFiles: [MyCoderAutoFreeTextFile] = []
        var warnings: [String] = []

        for file in files {
            guard let path = file.path, !path.isEmpty else {
                warnings.append("Attachment \(file.name) could not be read and was not sent to myCoder Auto Free.")
                continue
            }
            let url = URL(fileURLWithPath: path)
            let mime = MessagePartsBuilder.mimeType(for: file)
            if MessagePartsBuilder.isImageMimeType(mime) {
                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    imageDataURLs.append(MessagePartsBuilder.dataURL(
                        mimeType: mime,
                        base64: data.base64EncodedString()
                    ))
                } else {
                    warnings.append("Attachment \(file.name) is an unreadable image and was not sent to myCoder Auto Free.")
                }
            } else if MyCoderAutoFreeContentLogic.isUnsupportedForTextRoute(fileName: file.name, mimeType: mime) {
                warnings.append("Attachment \(file.name) is not supported by the free route and was not sent to myCoder Auto Free.")
            } else if let data = try? Data(contentsOf: url),
                      let content = String(data: data, encoding: .utf8) {
                let bounded = String(content.prefix(250_000))
                textFiles.append(MyCoderAutoFreeTextFile(name: file.name, content: bounded))
                if content.count > bounded.count {
                    warnings.append("Attachment \(file.name) was truncated to 250,000 characters for the free route.")
                }
            } else {
                warnings.append("Attachment \(file.name) is not a readable text/image file and was not sent to myCoder Auto Free.")
            }
        }

        return (
            MyCoderAutoFreeContentLogic.parts(
                text: text,
                imageDataURLs: imageDataURLs,
                textFiles: textFiles
            ),
            warnings
        )
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
        
        if sessionID != messageStore.currentSessionID { return }
        
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
            appState.pendingQuestionRequest = nil

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
        guard appState.pendingQuestionRequest == nil else { return }
        serveTimeoutTask?.cancel()
        serveTimeoutTask = nil
        appState.isLoading = false
        appState.isStreaming = false
        sseClient.disconnect()

        let assistantID = currentAssistantMessageID ?? ""
        let currentMessage = messageStore.messages.first(where: { $0.id == assistantID })
        let hasToolActivity = currentMessage?.parts.contains { part in
            switch part {
            case .toolCall, .stepStart, .stepFinish:
                return true
            case .text, .reasoning, .image, .routeInfo:
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
        refreshGitForCurrentSession()
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


struct AutoFreeSwitchBanner: View {
    let notification: AppNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.type.icon)
                .interfaceFont(size: 15, weight: .semibold)
                .foregroundColor(Color.mimo.error)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(notification.message)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.mimo.error.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.error.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
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
