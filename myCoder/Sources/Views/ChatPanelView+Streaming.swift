import SwiftUI
import AppKit

extension ChatPanelView {
    func buildACPMessages(text: String, files: [FileInfo], images: [ClipboardImage]) -> [ACPRequestMessage] {
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
                    self.syncExecutionSteps(from: msg.parts, sessionID: sessionID)
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
                        appState.setSteps(steps, for: sessionID)
                        appState.showGoal = true
                        GoalPlanSyncService.sync(
                            steps: steps,
                            context: appState.goalContext(for: sessionID)
                        )
                    }
                case "step-start":
                    msg.parts.append(.stepStart)
                    appState.showGoal = true
                case "step-finish":
                    msg.parts.append(.stepFinish)
                default:
                    break
                }
                self.syncExecutionSteps(from: msg.parts, sessionID: sessionID)
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
    func pauseForPendingQuestion() {
        appState.isLoading = false
        appState.isStreaming = false
    }

    @MainActor
    func syncExecutionSteps(from parts: [MessagePartContent], sessionID: String?) {
        let existing = appState.steps(for: sessionID)
        let synced = ExecutionStepSyncLogic.steps(from: parts, existing: existing)
        guard !synced.isEmpty else { return }
        appState.setSteps(
            ExecutionStepSyncLogic.mergedSteps(existing: existing, incoming: synced),
            for: sessionID
        )
        appState.showGoal = true
    }

    @MainActor
    func finishStreaming() {
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
        // Ход закончился: звук играет только если это был успешный ответ и
        // нет работающей цели (запрос 2026-11-13).
        playCompletionSoundIfIdle(endedWithError: isEmptyCompletion)
    }
}
