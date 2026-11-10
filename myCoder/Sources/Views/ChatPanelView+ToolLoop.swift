import Foundation
import AppKit

/// Декомпозиция `ChatPanelView` (audit B3): tool-loop-хелперы прямых
/// OpenAI-совместимых провайдеров вынесены из God-файла целиком, без
/// изменения тел. Никакого изменения поведения — только переезд в
/// отдельный extension-файл, чтобы `ChatPanelView.swift` уменьшался.
extension ChatPanelView {

    /// Стримит один ход напрямую в сообщение чата; при SSE-отказе
    /// провайдера (400/405/422/501) падает на одноразовый completion.
    ///
    /// Вход: endpoint/key/model, сообщения, параметры модели, id assistant-
    /// сообщения, текущий таймлайн. Выход: `DirectChatResult`.
    /// Зависимости: `DirectChatStreamer`, `DirectChatClient`, `messageStore`.
    func streamDirectChat(
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

    /// Стартует таймаут 90с для serve-хода: если локальный агент не
    /// ответил, сообщение честно обрывается с причиной.
    ///
    /// Вход: id assistant-сообщения. Выход: нет.
    /// Зависимости: `serveTimeoutTask`, `appState`, `messageStore`.
    func startServeTimeout(assistantID: String) {
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

    /// Строит launcher субагентов для текущей сессии/проекта.
    ///
    /// Вход: корень проекта, транспорт субагента, id чата.
    /// Выход: closure `(description, prompt) async -> String`.
    /// Зависимости: `SubagentRunner`, `appState`, `messageStore`.
    func subagentLauncher(
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

    /// Подготавливает локальные tool-вызовы: валидация, denial для
    /// read-only режимов, approval для требующих доступа.
    ///
    /// Вход: вызовы, модельный контекст, корень проекта, уровень доступа,
    /// режим агента. Выход: `[PreparedLocalToolCall]`.
    /// Зависимости: `WebToolProtocolEmulator`, `PlanModeToolPolicy`,
    /// `WebToolAccessGate`, `OutOfProjectAccessLogic`.
    func prepareLocalToolCalls(
        _ calls: [WebToolCall],
        modelContext: String,
        projectRoot: String,
        accessLevel: AccessLevel,
        agentMode: AgentMode
    ) -> [PreparedLocalToolCall] {
        calls.map { call in
            let callID = UUID().uuidString
            var validationError = WebToolProtocolEmulator.validate(
                call, projectRoot: projectRoot, accessLevel: accessLevel
            )
            if call.arguments["__mycoder_truncated"] == "1", validationError == nil {
                validationError = .incompleteJSON
            }
            // Plan/Compose modes are read-only: mutating tools are refused
            // right away, without a security prompt (user directive
            // 2026-10-30, extended to compose 2026-11-05).
            var denialReason: String?
            if case .deny(let reason) = PlanModeToolPolicy.decision(
                for: call, mode: agentMode
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
                      !PlanModeToolPolicy.bypassesApproval(for: call, mode: agentMode),
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
    enum OutOfProjectAccessOutcome {
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
    func resolveOutOfProjectAccess(
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

    /// Регистрирует все ожидающие approvals одного сообщения в центре
    /// approvals и показывает уведомления.
    ///
    /// Вход: approvals, id assistant-сообщения. Выход: нет.
    /// Зависимости: `ToolApprovalCenter`, `appState`, `messageStore`.
    @MainActor
    func enqueueLocalToolApprovals(
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

    /// Ждёт вердикт пользователя по одному approval.
    ///
    /// Вход: approval, id assistant-сообщения. Выход: Bool (approved).
    /// Зависимости: `ToolApprovalCenter`, `messageStore`, `appState`.
    @MainActor
    func awaitLocalToolApproval(
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

    /// Переприкрепляет ожидающие approvals после переключения чата.
    ///
    /// Вход: id сессии. Выход: нет.
    /// Зависимости: `ToolApprovalCenter`, `messageStore`.
    @MainActor
    func reattachPendingApprovals(sessionID: String) {
        let assistantIDs = Set(
            messageStore.messages
                .filter { $0.role == .assistant }
                .map(\.id)
        )
        let grouped = ToolApprovalCenter.shared.pendingApprovals(matchingAssistantIDs: assistantIDs)
        guard !grouped.isEmpty else { return }
        messageStore.setPendingApprovals(grouped)
    }

    /// Публикует таймлайн-части в сообщение чата (стриминг).
    ///
    /// Вход: части, id assistant-сообщения, опциональный контент.
    /// Выход: нет. Зависимости: `messageStore`.
    @MainActor
    func publishToolParts(
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

    /// Проигрывает звук для ожидающего approval.
    ///
    /// Вход: нет. Выход: нет. Зависимости: `NSSound`.
    func playLocalApprovalSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
