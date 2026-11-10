import SwiftUI
import AppKit

/// Everything the send coordinator needs after validation, session selection
/// and the optimistic user bubble. A nil result means the send was rejected
/// and already reported to the user.
struct DirectSendPreparationResult {
    var assistantID: String
    var selectedID: String?
    var messageID: String
    var agentMode: AgentMode
    var sendOptions: MessageSendOptions
    var localProviders: [LocalProviderConfig]
    var route: SendRoute
    var turnSessionID: String?
    var capturedProjectRoot: String
    var capturedToolRoot: String
    var capturedModelID: String
    var capturedParameters: ModelCallParameters
    var priorTurnsForContext: [ChatHistoryBuilder.Turn]
    var earlyPreparedSessionID: String?
    var sendSessionID: String?
    var appendedUserMessageID: String?
    var earlySendInfo: MessageSendInfo
}

extension ChatPanelView {
    /// Validates the turn, resolves its route, creates/selects the chat and
    /// appends the optimistic user bubble. Returns nil after reporting a
    /// rejected send, so the caller never continues with a half-built turn.
    func prepareDirectSendTurn(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage],
        agentModeOverride: AgentMode?,
        retryPlan: SessionBusyRetryLogic.RetryPlan?,
        existingUserMessageID: String?,
        explicitSessionID: String?
    ) async -> DirectSendPreparationResult? {
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
            return nil
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
            return nil
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
        // The context collection must use the project of the OPEN CHAT, not
        // the globally selected workspace (user check 2026-11-08: a myCoder
        // chat collected llama.cpp context because llama.cpp was selected).
        // The session owns its project; the workspace is only the fallback
        // for chats that do not have one yet.
        let sessionProjectRoot = await MainActor.run { () -> String in
            guard let turnSessionID,
                  let session = appState.sessions.first(where: { $0.id == turnSessionID }) else {
                return ""
            }
            return session.directory
        }
        let capturedProjectRoot = SessionProjectRootLogic.resolve(
            sessionDirectory: sessionProjectRoot,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
        let capturedToolRoot = appState.toolWorkingDirectory
        let capturedModelID = appState.effectiveSelectedModel()
        let capturedParameters = ModelCallParametersStore.parameters(for: capturedModelID)
        // The context-assembly log opens with the user's own request; every
        // later action is recorded against it (user directive 2026-11-07).
        // It belongs to the chat that started the turn (C1), so it opens only
        // after the session id is known — see `sendSessionID` below.
        // A model switch into a smaller context window compacts the chat
        // before it continues: the turn waits for that compaction, otherwise
        // the history would be built from messages that are about to be
        // replaced by a summary.
        await awaitModelSwitchCompactionIfNeeded()
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
        // The context-assembly journal belongs to the chat that started the
        // turn (C1): open it only now that the session id is known, then close
        // the request stage with the real history/project facts.
        await MainActor.run {
            appState.beginContextAssembly(
                message: text,
                projectRoot: capturedProjectRoot,
                sessionID: sendSessionID
            )
            appState.finishContextAction(
                key: ContextAssemblyLogLogic.requestKey,
                result: "История: \(priorTurnsForContext.count) ход(ов); проект: \(capturedProjectRoot.isEmpty ? "не открыт" : capturedProjectRoot)",
                sessionID: sendSessionID
            )
        }
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
        return DirectSendPreparationResult(
            assistantID: assistantID,
            selectedID: selectedID,
            messageID: messageID,
            agentMode: agentMode,
            sendOptions: sendOptions,
            localProviders: localProviders,
            route: route,
            turnSessionID: turnSessionID,
            capturedProjectRoot: capturedProjectRoot,
            capturedToolRoot: capturedToolRoot,
            capturedModelID: capturedModelID,
            capturedParameters: capturedParameters,
            priorTurnsForContext: priorTurnsForContext,
            earlyPreparedSessionID: earlyPreparedSessionID,
            sendSessionID: sendSessionID,
            appendedUserMessageID: appendedUserMessageID,
            earlySendInfo: earlySendInfo
        )
    }
}
