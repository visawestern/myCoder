import SwiftUI
import AppKit

extension ChatPanelView {
    @MainActor
    func syncBackgroundActivity() {
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
    var visibleSessionIsStreaming: Bool {
        guard let sessionID = messageStore.currentSessionID else { return false }
        return appState.streamingSessionIDs.contains(sessionID)
    }

    func editMessageFromNotification(_ notification: Notification) {
        guard let messageID = notification.userInfo?["messageId"] as? String,
              let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
        loadMessageIntoComposer(message)
    }

    /// Полноценный откат диалога к запросу пользователя: план → аудитор →
    /// безопасное исполнение (корзина+снапшоты) → урезание чата → чип.
    @MainActor
    func handleRollbackRequest(_ notification: Notification) {
        guard let messageID = notification.userInfo?["messageId"] as? String else { return }
        let sessionID = (notification.userInfo?["chatId"] as? String)
            ?? appState.selectedSession?.id
        guard let sessionID else { return }
        Task {
            await performRollback(targetMessageID: messageID, sessionID: sessionID)
        }
    }

    @MainActor
    func performRollback(targetMessageID: String, sessionID: String) async {
        // Живой фид, если чат открыт; иначе — полный срез из БД (API-откат
        // невыбранного чата). `RollbackDialogueLoader` — чистая функция с тестами.
        let messages = RollbackDialogueLoader.resolve(
            for: sessionID,
            fromStore: { messageStore.messages(in: sessionID) },
            fromDatabase: { DatabaseBridge.shared.loadMessages(sessionId: $0) }
        )
        guard !messages.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Проект отката определяется сессией, а не тем, что открыто в
        // сайдбаре: API-откат может относиться к другому чату. Для чата без
        // проекта рабочий каталог — домашний, как и при выполнении
        // инструментов (`ProjectlessWorkspaceLogic`).
        let sessionDirectory = DatabaseBridge.shared.sessionDirectory(forSessionID: sessionID)
        let projectPath = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: sessionDirectory,
            workspacePath: appState.selectedWorkspace?.path,
            homeDirectory: home.path
        )

        let input = RollbackContextBuilder.build(from: messages)
        let entries = RollbackUndoLoader.load(
            sessionID: sessionID, projectPath: projectPath, homeDirectory: home)

        let context = RollbackCoordinatorContext(
            targetMessageID: targetMessageID,
            messages: input.messages,
            undoEntries: entries,
            irreversibleActions: input.irreversibleActions,
            snapshotRestoring: RollbackSnapshotRestorer(projectPath: projectPath),
            trashStoring: RollbackTrashStore(homeDirectory: home),
            undoMarking: RollbackUndoMarker(projectPath: projectPath)
        )

        let chip = await RollbackCoordinator.run(context: context, auditor: internalAuditor)

        let deps = RollbackChatApplier.Dependencies(
            messages: messages,
            sessionID: sessionID,
            homeDirectory: home,
            removeMessage: { id in
                // Когда фид не загружен (API-откат невыбранного чата),
                // `MessageStore.remove` вернёт false и не тронет БД — поэтому
                // удаление дублируется напрямую в БД.
                if !self.messageStore.remove(id: id) {
                    DatabaseBridge.shared.deleteMessage(id: id)
                }
            },
            appendMessage: { msg in
                self.messageStore.append(msg, to: sessionID)
            },
            restorePrompt: { text in
                self.messageText = text
            }
        )
        try? RollbackChatApplier.apply(chip: chip, dependencies: deps)
    }

    /// Аудитор отката: внутренняя модель (если доступна). При недоступности
    /// координатор честно переходит на детерминированный план.
    var internalAuditor: RollbackCoordinator.Auditor {
        { system, user in
            try await InternalModelRunner.complete(messages: [
                DirectChatMessage(role: "system", content: system),
                DirectChatMessage(role: "user", content: user),
            ])
        }
    }

    func resendMessageFromNotification(_ notification: Notification) {
        guard let messageID = notification.userInfo?["messageId"] as? String,
              let message = messageStore.messages.first(where: { $0.id == messageID }) else { return }
        resendMessage(message)
    }

    func handleAPISendRequest(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? String, !message.isEmpty else { return }
        if let chatId = notification.userInfo?["chatId"] as? String, !chatId.isEmpty {
            messageStore.currentSessionID = chatId
        }
        messageText = message
        sendMessage()
    }

    /// Stop / roll back / repeat the model-switch compaction from outside the
    /// app (the HTTP API). The banner offers the same actions — this is the
    /// same code path, not a second implementation.
    @MainActor
    func handleAPICompactionControl(_ notification: Notification) {
        guard let control = notification.userInfo?["action"] as? String else { return }
        switch control {
        case "stop":
            stopModelSwitchCompaction()
        case "rollback":
            rollbackModelSwitchCompaction()
        case "retry":
            retryModelSwitchCompaction()
        case "chooseModel":
            chooseAlternativeModelFromNotice(notification)
        default:
            break
        }
    }

    /// Pick one of the offered alternatives (the banner's model menu) from
    /// outside the app. Only the models the banner offers can be chosen — the
    /// notice is the list of models that hold the context without compaction.
    @MainActor
    func chooseAlternativeModelFromNotice(_ notification: Notification) {
        guard let providerID = notification.userInfo?["providerID"] as? String,
              let modelID = notification.userInfo?["modelID"] as? String,
              let notice = appState.modelSwitchCompactionNotice,
              let candidate = notice.alternatives.first(where: {
                  $0.providerID == providerID && $0.id == modelID
              }) else { return }
        chooseLargerModel(candidate)
    }

    func handleLocalToolApprovalResolved(_ notification: Notification) {
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

    func handleWebToolApprovalResolved(_ notification: Notification) {
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

    func copyEntireChat() {
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
    
    var displayMessages: [Message] {
        MessageDisplayLogic.messagesForDisplay(messageStore.messages)
    }
    
    func workedSeparator(before index: Int, in messages: [Message]) -> String? {
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
    func flushPendingSpecNodePrompt() {
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
}
