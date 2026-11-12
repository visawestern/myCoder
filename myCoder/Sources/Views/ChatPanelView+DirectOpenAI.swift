import SwiftUI
import AppKit

extension ChatPanelView {
    /// Runs one direct OpenAI-compatible turn: history assembly, text tool
    /// protocol loop, approvals and final persistence. Extracted from
    /// `performDirectSend` to keep both functions inside the module budget.
    func runOpenAICompatibleDirectTurn(
        baseURL: String,
        apiKey: String?,
        model: String,
        assistantID: String,
        sendSessionID: String?,
        modelText: String,
        files: [FileInfo],
        images: [ClipboardImage],
        preparation: SendContextPreparation,
        sysPrompt: String,
        agentMode: AgentMode,
        isProjectlessTurn: Bool
    ) async {
        let params = ModelCallParametersStore.parameters(for: model)
        // Prior turns = everything strictly before the current user message.
        // `dropLast(2)` was wrong: a warning notice inserted before the
        // assistant placeholder cut a real answer out of history (audit P1).
        let prior = await MainActor.run { () -> [ChatHistoryBuilder.Turn] in
            let msgs = messageStore.messages(in: sendSessionID)
            let modelHistory = ConversationCompactionLogic.historyForModel(msgs)
            let history = DirectHistorySelectionLogic.priorTurns(from: modelHistory)
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
            sessionId: sendSessionID,
            messageId: assistantID,
            isProjectless: isProjectlessTurn
        )
        executor.projectlessWritePrompt = { suggested in
            await self.promptCreateProjectForFileWrite(
                suggestedName: suggested,
                sessionID: sendSessionID
            )
        }
        executor.subagentLauncher = subagentLauncher(
            projectRoot: projectRoot,
            transport: routedSubagentTransport(fallback: .openAICompatible(baseURL: URL(string: baseURL) ?? URL(fileURLWithPath: "/"), apiKey: apiKey ?? "", model: model)),
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
                        // Битый блок — тоже «прописанный» вызов: он
                        // обязан попасть под спойлер с причиной, а не
                        // исчезнуть из чата.
                        if let malformed = WebToolProtocolEmulator.malformedToolCall(from: response) {
                            timelineParts.append(UnexecutedToolCallLogic.part(
                                name: malformed.name,
                                arguments: [:],
                                callID: UUID().uuidString,
                                reason: .malformedBlock(malformed.problem)
                            ))
                            publishToolParts(
                                AssistantTurnPartsLogic.directTimelineParts(
                                    timeline: timelineParts,
                                    answer: ""
                                ),
                                assistantID: assistantID
                            )
                        }
                        conversation.append(DirectChatMessage(role: "assistant", content: response))
                        conversation.append(DirectChatMessage(role: "user", content: feedback))
                        continue
                    }
                    // Лимит итераций: вызовы прописаны, но уже не
                    // будут исполнены. Показываем их спойлерами с
                    // конкретной причиной — как ошибки валидации.
                    if !calls.isEmpty {
                        let prose = ToolProtocolStripping.visibleText(from: response)
                        if !prose.isEmpty {
                            timelineParts.append(.text(prose))
                        }
                        timelineParts.append(contentsOf: UnexecutedToolCallLogic.parts(
                            for: calls,
                            reason: .iterationLimit(maxIterations)
                        ))
                        publishToolParts(
                            AssistantTurnPartsLogic.directTimelineParts(
                                timeline: timelineParts,
                                answer: ""
                            ),
                            assistantID: assistantID
                        )
                        // Проза уже в таймлайне — не дублируем её
                        // финальным ответом.
                        finalText = ""
                        break
                    }
                    // Финальный текст не должен содержать сырой протокол
                    // вызова, даже если модель так и не дала ответ.
                    finalText = ToolProtocolStripping.visibleText(from: response)
                    break
                }
                // Fix the model's prose for this iteration BEFORE its
                // tool calls so no server response is lost: the order is
                // reasoning → prose → calls → results → next iteration.
                // Все протоколы вызовов (DSML/```tool/Anthropic) и
                // статус-строки уходят из текста: вызовы уже
                // отрисованы отдельными tool-call частями.
                let iterationProse = ToolProtocolStripping.visibleText(from: response)
                if !iterationProse.isEmpty {
                    timelineParts.append(.text(iterationProse))
                }
                let prepared = prepareLocalToolCalls(
                    calls,
                    modelContext: response,
                    projectRoot: projectRoot,
                    accessLevel: appState.accessLevel,
                    agentMode: agentMode
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
                    // U5: локальный todo_write/task_* пишет todos.json,
                    // но панель обновлялась только по SSE. Читаем
                    // сохранённый чеклист сразу после исполнения —
                    // единый источник правды для всех путей.
                    if TodoPanelSyncLogic.updatesChecklist(toolName: item.call.name) {
                        let todoItems = executor.loadTodoItems()
                        let steps = TodoPanelSyncLogic.steps(
                            fromTodoItems: todoItems
                        )
                        await MainActor.run {
                            self.appState.setSteps(steps, for: sendSessionID)
                            if !steps.isEmpty { self.appState.showGoal = true }
                            GoalPlanSyncService.sync(
                                todoItems: todoItems,
                                context: self.appState.goalContext(for: sendSessionID)
                            )
                        }
                    }
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
                // Всё, что осталось без результата (отмена, не
                // дождались approve), всё равно должно быть видно
                // под спойлером с конкретной причиной.
                let unfinishedReason: ToolCallSkipReason =
                    Task.isCancelled ? .cancelled : .awaitingApproval
                var markedUnexecuted = false
                for item in prepared {
                    let handled = timelineParts.contains { part in
                        if case .toolCall(_, _, let result, let id) = part, id == item.callID {
                            return result != nil
                        }
                        return false
                    }
                    if !handled {
                        timelineParts = localToolParts(
                            timelineParts,
                            settingResult: unfinishedReason.text,
                            callID: item.callID
                        )
                        markedUnexecuted = true
                    }
                }
                if markedUnexecuted {
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
                // Если цикл закончится на этом шаге (лимит/отмена),
                // видимым текстом останется чистая проза, а не сырой
                // протокол вызова.
                finalText = iterationProse
                await MainActor.run {
                    let reasoning = DirectChatClient.mergedReasoning(reasoningChunks)
                    self.messageStore.update(id: assistantID) { msg in
                        // Никаких «⏳ Running tools...»: статус не
                        // должен застревать в сохранённом сообщении.
                        msg.content = iterationProse
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
                    msg.content = ToolProtocolStripping.visibleText(from: finalText)
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
                // Успешный ответ прямой модели — звук завершения, если нет
                // работающей цели (запрос 2026-11-13).
                self.playCompletionSoundIfIdle()
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
                        // Отмена могла оставить в тексте сырой блок
                        // вызова и статус-строку — чистим.
                        msg.content = ToolProtocolStripping.visibleText(from: msg.content)
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
}
}
