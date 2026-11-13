import SwiftUI
import AppKit

extension ChatPanelView {
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
            chatRowFrames = [:]
            currentUserMessageID = nil
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
                    // The server may return rows that were never persisted
                    // locally; merge them so the navigator lists the whole
                    // session instead of only the tail.
                    messageStore.refreshNavigatorIndex(
                        sessionId: sessionID,
                        using: loadedMessages.map { MessageStore.message(from: $0) }
                    )
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
                settleAtBottom()
                flushPendingSpecNodePrompt()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard messageStore.currentSessionID == sessionID else { return }
                    canLoadOlderMessages = true
                }
            }
        }
    }
    
    @MainActor
    func recordRejectedSend(text: String,
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
    func prepareSessionBeforeAppending(
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
            case .goal(let goalCommand):
                messageText = ""
                Task { await self.runGoalCommand(goalCommand) }
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
    func appendOptimisticUserMessage(_ queued: QueuedMessage) async -> String? {
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

    func restoreStashedDraftIfNeeded() {
        composerHoldsQueuedMessage = false
        guard restoreStashedDraftAfterSend, let draft = stashedComposerDraft else { return }
        messageText = draft.text
        attachmentStore.replaceImages(draft.images)
        attachmentStore.replaceFiles(draft.files)
        stashedComposerDraft = nil
        restoreStashedDraftAfterSend = false
    }

    /// Applies a slash-command effect to real app state (E08, Раздел 5 п.12-16).
    func applySlashEffect(_ effect: SlashEffect) {
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
}
