import SwiftUI
import AppKit

extension ChatPanelView {
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
    func updateCurrentVisibleUserMessage(snapshot: ChatScrollBridge.Snapshot? = nil) {
        let current = snapshot ?? ChatScrollBridge.shared.currentSnapshot()
        guard current.viewportHeight > 0 else { return }
        // Кадры строк — в content-пространстве, поэтому видимая область —
        // это просто [offsetY, offsetY + viewportHeight].
        let visible = CGRect(x: 0, y: current.offsetY, width: 1, height: current.viewportHeight)
        let resolved = UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: visible,
            frames: userRowFrames,
            messages: displayMessages
        )
        // Обновляем только при смене сообщения: иначе скролл перестраивал бы
        // навигатор и весь чат на каждом кадре.
        if currentUserMessageID != resolved {
            currentUserMessageID = resolved
        }
    }

    /// Loads one older page and keeps the reader's current question in place.
    /// Without this anchor, prepending rows pushes the visible turn down and
    /// the chat appears to jump to unrelated history.
    func loadOlderMessages(proxy: ScrollViewProxy) {
        guard let sessionID = messageStore.currentSessionID else { return }
        guard !messageStore.isLoadingOlder else { return }  // Prevent cascade
        let before = ChatScrollBridge.shared.currentSnapshot()
        let anchorMessageID = ChatPaginationLogic.visibleAnchor(
            frames: userRowFrames,
            offsetY: before.offsetY
        )
            ?? currentUserMessageID
            ?? displayMessages.last(where: { $0.role == .user })?.id
        // Первый реально видимый user-row сохраняет позицию. Если на экране
        // только длинный ответ, используем ближайший известный user-row;
        // latest-row всё равно измеряется для следящей прокрутки.
        let countBefore = messageStore.messages.count
        // Запоминаем точку привязки ДО вставки. После подгрузки та же строка
        // уедет вниз ровно на высоту страницы — компенсируем это смещением
        // скролла в том же layout-проходе, без отдельного `scrollTo`.
        if let anchorMessageID, let frame = userRowFrames[anchorMessageID] {
            pendingPaginationAnchor = PaginationAnchor(
                messageID: anchorMessageID,
                oldMinY: frame.minY,
                oldOffset: before.offsetY
            )
        } else {
            pendingPaginationAnchor = nil
        }

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
                // Страница не добавилась — якорь не сдвинется, снимаем его,
                // иначе он навсегда заблокирует prefetch.
                if messageStore.messages.count == countBefore {
                    pendingPaginationAnchor = nil
                }
                // Fallback: якорь не отчитался кадром (не user-строка).
                if pendingPaginationAnchor == nil, let anchorMessageID {
                    DispatchQueue.main.async {
                        proxy.scrollTo(anchorMessageID, anchor: .top)
                    }
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
}
