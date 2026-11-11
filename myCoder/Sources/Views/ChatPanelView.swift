import SwiftUI
import AppKit

func localToolParts(
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
struct ComposerDraftSnapshot {
    let text: String
    let files: [FileInfo]
    let images: [ClipboardImage]

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && files.isEmpty
            && images.isEmpty
    }
}

/// Точка привязки для подгрузки истории: строка, которая была на экране до
/// вставки страницы, её прежняя content-relative позиция и прежний offset.
/// После вставки компенсируем сдвиг строки тем же смещением скролла.
struct PaginationAnchor {
    let messageID: String
    let oldMinY: CGFloat
    let oldOffset: CGFloat
}

struct PreparedLocalToolCall {
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
    @StateObject var messageStore = MessageStore()
    @StateObject var messageQueue = MessageQueue()
    @StateObject var attachmentStore = MessageAttachmentStore()
    @State var messageText = ""
    @State var stashedComposerDraft: ComposerDraftSnapshot?
    @State var restoreStashedDraftAfterSend = false
    @State var composerHoldsQueuedMessage = false
    @State var showFilePicker = false
    @State var streamingText = ""
    @State var currentAssistantMessageID: String?
    @State var currentTask: Task<Void, Never>?
    @State var previousSessionID: String?
    @State var isChatBottomVisible = true
    /// Последняя известная высота контента: рост при ленивой раскладке
    /// отличается от пользовательского скролла (offset не меняется, maxY растёт).
    @State var lastKnownMaxOffset: CGFloat = 0
    /// Content-relative frames of user rows. Stable during scrolling (unlike
    /// the old scroll-space frames that changed every tick and made the view
    /// re-evaluate per frame).
    @State var userRowFrames: [String: CGRect] = [:]
    /// Latest assistant row bottom in content coordinates. Unlike a document
    /// maximum this anchor remains valid when streamed text is replaced by a
    /// much shorter tool card.
    @State var latestContentBottom: CGFloat = 0
    /// Viewport measured once by the existing AppKit bridge; used only to size
    /// the streaming follow tail, not for per-frame SwiftUI preferences.
    @State var chatViewportHeight: CGFloat = 0
    /// Anchor captured before a history page is prepended. When the anchor row
    /// reports its new content-relative frame, the scroll offset is shifted by
    /// the same delta — the viewport stays visually still (messenger behaviour).
    @State var pendingPaginationAnchor: PaginationAnchor?
    /// Timestamp of the user's last wheel scroll: auto-scroll is suppressed
    /// right after, so reading older messages is never yanked back.
    @State var lastUserScrollAt = Date.distantPast
    /// Direction of the user's last wheel gesture. While it is `.up`, the
    /// auto-scroll is suppressed for `upwardReadingProtection` so a growing
    /// answer below never yanks the reader out of older content (user report
    /// 2026-11-01: «прокрутка стопорится / прокручивает сразу куском»).
    @State var lastUserWheelDirection: ChatScrollLogic.WheelDirection?
    /// Timestamp of the last auto-scroll (throttle).
    @State var lastAutoScrollAt = Date.distantPast
    /// One scheduled auto-scroll at a time (coalescing).
    @State var pendingAutoScrollTask: Task<Void, Never>?
    /// Message count / newest id of the last revision: growth of the count
    /// AND a new newest id means a new message was appended (not older
    /// messages prepended by history pagination).
    @State var lastKnownMessageCount = 0
    @State var lastKnownLastMessageID: String?
    @State var scrollEventMonitor: Any?
    @State var currentUserMessageID: String?
    @State var canLoadOlderMessages = false
    @State var scrolledSessionID: String?
    /// Message to outline after a notification tap jumps to it.
    @State var highlightedMessageID: String?
    @State var highlightClearTask: Task<Void, Never>?
    @State var focusLoadingTask: Task<Void, Never>?
    @State var draftSaveTask: Task<Void, Never>?
    @State var serveTimeoutTask: Task<Void, Never>?
    @State var isCompacting = false
    /// Task of the automatic compaction that follows a model switch into a
    /// smaller context window. It is kept here so the user can stop it and
    /// so the send path can wait for it before building the history.
    @State var modelSwitchCompactionTask: Task<Void, Never>?
    /// Generation counter of the model-switch compaction. A finished task may
    /// only update the notice it started — a retry must not be overwritten by
    /// the previous attempt.
    @State var modelSwitchCompactionGeneration = 0
    /// Model that was selected before the last switch: the notice names both.
    @State var lastSelectedModel = ""
    @State var activeWebProviderID: String?
    @State var activeWebChatID: String?
    @State var webCatalogRefreshKeys: Set<String> = []
    @State var captchaSolverContext: WebCaptchaSolverContext?
    /// Approval mailbox of the CURRENT web-agent turn: the Allow/Deny card
    /// resolves the pending request through this box.
    @State var activeApprovalBox: WebToolApprovalBox?
    /// Minimap vs half-chat panel (user directive 2026-09-09: minimap by
    /// default, expand on tap). Persisted so the choice survives restarts.
    @AppStorage("mycoder.webBrowserPanelExpanded") var webBrowserPanelExpanded = false
    let sseClient = SSEClient()
    let db = DatabaseManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // User directive 2026-09-09: for a web provider the live vendor
            // page is VISIBLE in the chat — a small minimap thumbnail by
            // default (bottom-trailing overlay, expands on tap), or the
            // half-chat panel when expanded. Both show the AntiBrowser cast
            // of the provider's tab, so the page — login, conversation,
            // in-flight stream — survives across requests; switching chats moves the
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
                                        .chatRowFrameReporter(
                                            id: message.id,
                                            isUser: message.role == .user,
                                            isLatest: message.id == displayMessages.last?.id
                                        )
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(ChatScrollLogic.bottomAnchorID)

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
                            .padding(.bottom, 16 + ChatScrollLogic.bottomContentInset
                                + ChatScrollLogic.followTailHeight(
                                    viewportHeight: chatViewportHeight,
                                    isStreaming: displayMessages.last?.isStreaming == true
                                ))
                            // Кадры строк считаются в content-пространстве:
                            // они не меняются при скролле, поэтому preference
                            // не дёргает вью на каждом кадре.
                            .coordinateSpace(name: ChatScrollSpace.content)
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
                            handleUserRowFrames(value)
                        }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            updateCurrentVisibleUserMessage()
                        }
                        .onChange(of: ChatScrollLogic.revision(messages: displayMessages)) { _ in
                            autoScrollIfPinned()
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
                            // Один AppKit-наблюдатель вместо трёх
                            // GeometryReader-preferences на каждый кадр.
                            ChatScrollBridge.shared.onScroll = { snapshot in
                                applyScrollSnapshot(snapshot, proxy: proxy)
                            }
                            applyScrollSnapshot(ChatScrollBridge.shared.currentSnapshot(), proxy: proxy)
                        }
                        .onDisappear {
                            pendingAutoScrollTask?.cancel()
                            removeScrollWheelMonitor()
                            ChatScrollBridge.shared.onScroll = nil
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

                    // A model switch into a smaller context window compacts
                    // the chat before it continues. The banner is the visible
                    // control of that compaction: stop, rollback, retry, or
                    // pick a model with a larger window.
                    if let notice = appState.modelSwitchCompactionNotice {
                        ModelSwitchCompactionBanner(
                            notice: notice,
                            onStop: { stopModelSwitchCompaction() },
                            onRollback: { rollbackModelSwitchCompaction() },
                            onRetry: { retryModelSwitchCompaction() },
                            onChooseModel: { chooseLargerModel($0) },
                            onDismiss: { dismissModelSwitchCompactionNotice() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
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
        .onChange(of: appState.selectedSession?.id) { newSessionID in
            handleSelectedSessionChange(newSessionID)
        }
        .onChange(of: appState.selectedWorkspace?.path) { _ in
            // M1: switching project changes which project-default routing
            // applies, so reload configuration + journal for the new root.
            reloadModelRouting()
        }
        .onChange(of: appState.effectiveSelectedModel()) { newModel in
            handleModelSwitch(to: newModel)
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
        .onReceive(NotificationCenter.default.publisher(for: .rollbackRequested)) { notification in
            handleRollbackRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopGeneration)) { _ in
            stopGeneration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiSendRequested)) { notification in
            handleAPISendRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiCompactionControlRequested)) { notification in
            handleAPICompactionControl(notification)
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



}

