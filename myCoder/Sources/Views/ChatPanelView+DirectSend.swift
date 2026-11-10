import SwiftUI
import AppKit

extension ChatPanelView {
    func performDirectSend(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage] = [],
        agentModeOverride: AgentMode? = nil,
        retryCount: Int = 0,
        retryPlan: SessionBusyRetryLogic.RetryPlan? = nil,
        existingUserMessageID: String? = nil,
        sessionID explicitSessionID: String? = nil
    ) async {
        guard let prepared = await prepareDirectSendTurn(
            text: text,
            files: files,
            images: images,
            agentModeOverride: agentModeOverride,
            retryPlan: retryPlan,
            existingUserMessageID: existingUserMessageID,
            explicitSessionID: explicitSessionID
        ) else { return }
        let assistantID = prepared.assistantID
        let selectedID = prepared.selectedID
        let messageID = prepared.messageID
        let agentMode = prepared.agentMode
        let sendOptions = prepared.sendOptions
        let localProviders = prepared.localProviders
        let route = prepared.route
        let turnSessionID = prepared.turnSessionID
        let capturedProjectRoot = prepared.capturedProjectRoot
        let capturedToolRoot = prepared.capturedToolRoot
        let capturedModelID = prepared.capturedModelID
        let capturedParameters = prepared.capturedParameters
        let priorTurnsForContext = prepared.priorTurnsForContext
        let earlyPreparedSessionID = prepared.earlyPreparedSessionID
        let sendSessionID = prepared.sendSessionID
        let appendedUserMessageID = prepared.appendedUserMessageID
        let earlySendInfo = prepared.earlySendInfo
        let needsContextPrep = true
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
        let directContext = await collectDirectSendContext(
            projectRoot: pointContextProjectRoot,
            hasProject: hasProjectForContext,
            needsContextPrep: needsContextPrep,
            sendSessionID: sendSessionID,
            turnSessionID: turnSessionID,
            agentMode: agentMode,
            priorTurnsForContext: priorTurnsForContext,
            text: text
        )
        let pointContextRecords = directContext.pointContextRecords
        let projectMemories = directContext.projectMemories
        let taskLedger = directContext.taskLedger
        let contextWarning = directContext.contextWarning
        let localPlan = directContext.localPlan
        let preparedBoard = directContext.preparedBoard
        let impactReport = directContext.impactReport
        let impactTimedOut = directContext.impactTimedOut
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
        await MainActor.run {
            appState.startContextAction(
                key: ContextAssemblyLogLogic.systemKey,
                title: "Системная инструкция",
                request: "Модель: \(capturedModelID); проект: \(capturedProjectRoot.isEmpty ? "не открыт" : capturedProjectRoot); режим: \(agentMode.rawValue)",
                processing: "Собираю правила проекта, режим работы и правила провайдера",
                sessionID: sendSessionID
            )
        }
        let sysPrompt = TurnDelivery.systemInstruction(
            route: route,
            userRules: [webUserRules, turnParams.systemPrompt ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            projectRoot: turnProjectRoot,
            isProject: !capturedProjectRoot.isEmpty,
            agentMode: agentMode
        )
        await MainActor.run {
            appState.finishContextAction(
                key: ContextAssemblyLogLogic.systemKey,
                result: sysPrompt.isEmpty
                    ? "Системная инструкция пуста."
                    : "Инструкция: \(sysPrompt.utf8.count) Б.",
                status: sysPrompt.isEmpty ? .warning : .done,
                sessionID: sendSessionID
            )
        }
        // Prior turns already computed above (before any potentially heavy
        // project scan) — do not recompute.
        await MainActor.run {
            appState.setContextStage(
                ContextStageLogLogic.line(for: .files),
                sessionID: sendSessionID
            )
        }
        // What the compiler is about to look at — captured once so the log can
        // name the real inputs of every stage.
        let skillsDirectory = MyCoderPaths.skillsDir(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let mergedPlan = TurnContextCompiler.merged(ContextQueryPlanner.plan(for: text), with: localPlan?.plan)
        let contextQuery = (mergedPlan.terms + mergedPlan.symbols + mergedPlan.files).joined(separator: " ")
        let evidenceQuery = ([text] + mergedPlan.symbols + mergedPlan.terms).joined(separator: " ")
        let indexedFileCount = pointContextRecords.count
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
            skillsDirectory: skillsDirectory,
            impact: impactReport,
            onStage: { stage in
                // The compiler runs off the main actor; the composer line is
                // UI state. Hop back for each real stage instead of leaving
                // the graph/skills steps invisible (user directive п.2).
                let line = ContextStageLogLogic.line(for: stage)
                let request: String
                switch stage {
                case .skills:
                    request = "Каталог скиллов: \(skillsDirectory.path)\nЗапрос: \(evidenceQuery)"
                case .graph:
                    request = "Запрос к графу: \(contextQuery)\nФайлов в индексе: \(indexedFileCount)"
                case .files:
                    request = "Бюджет: \(TurnContextCompiler.defaultBudgetTokens) токенов\nКандидатов: до \(TurnContextCompiler.defaultMaxFiles)\nЗапрос: \(contextQuery)"
                case .impact:
                    request = "Запрос: \(text)"
                default:
                    request = ""
                }
                DispatchQueue.main.async {
                    appState.setContextStage(line, sessionID: sendSessionID)
                    appState.startContextAction(
                        key: stage.rawValue,
                        title: ContextAssemblyLogLogic.title(for: stage),
                        request: request,
                        processing: line,
                        sessionID: sendSessionID
                    )
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
            appState.setContextStage(
                ContextStageLogLogic.doneLine(
                    fileCount: preparation.pack?.manifest.included.count ?? 0,
                    memoryCount: preparation.pack?.memoryIDs.count ?? 0,
                    hasGraph: preparation.pack?.sections.contains { $0.title == "Граф кода" } ?? false,
                    hasImpact: preparation.pack?.sections.contains { $0.title.contains("зависимостях") } ?? false
                ),
                sessionID: sendSessionID
            )
            // Close the journal: every action now has its real outcome, and
            // the skipped ones say why they were skipped.
            appState.completeContextAssembly(ContextAssemblyLogLogic.Facts(
                preparation: preparation,
                projectRoot: pointContextProjectRoot,
                contextEnabled: appState.isPointContextEnabled,
                plannerEnabled: appState.isLocalQueryPlannerEnabled,
                impact: impactReport,
                impactTimedOut: impactTimedOut,
                systemPromptBytes: sysPrompt.utf8.count,
                historyTurnCount: priorTurnsForContext.count
            ), sessionID: sendSessionID)
            appState.endContextCompilation(sessionID: sendSessionID)
        }
        let modelText: String
        switch route {
        case .openAICompatible, .web:
            modelText = preparation.modelText
        default:
            modelText = TurnDelivery.withSystem(sysPrompt, modelText: preparation.modelText)
        }
        // Когда пакета нет, `contextParts` пуст — тогда в `MessageRowView`
        // срабатывает `contextSummaryButton` с честной причиной, а не
        // запасной фолбэк-часть (которая навсегда прятала причину).
        let contextParts = SendContextPreparationLogic.contextParts(preparation)
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

        // M1: per-role routing executes the whole role graph locally. It runs
        // BEFORE the route guard: a routed send never uses the composer's
        // nominal provider branch, and each node fails honestly on its own.
        if appState.modelRoutingConfiguration.mode == .perRole {
            await runRoutedTurn(
                assistantID: assistantID,
                sendSessionID: sendSessionID,
                request: TurnDelivery.withSystem(sysPrompt, modelText: preparation.modelText),
                files: files,
                images: images,
                agentMode: agentMode
            )
            return
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
                try await runOpenCodeServeDirectTurn(
                    baseURL: baseURL,
                    headers: headers,
                    providerID: providerID,
                    model: model,
                    assistantID: assistantID,
                    earlyPreparedSessionID: earlyPreparedSessionID,
                    modelText: modelText
                )
                return
            }

            // ── Local / custom OpenAI-compatible branch ──────────
            if case .openAICompatible(let baseURL, let apiKey, let model) = route {
                await runOpenAICompatibleDirectTurn(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    assistantID: assistantID,
                    sendSessionID: sendSessionID,
                    modelText: modelText,
                    files: files,
                    images: images,
                    preparation: preparation,
                    sysPrompt: sysPrompt,
                    agentMode: agentMode
                )
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

            if try await runACPDirectTurn(
                route: route,
                localProviders: localProviders,
                assistantID: assistantID,
                modelText: modelText,
                files: files,
                images: images,
                agentModeOverride: agentModeOverride,
                text: text
            ) {
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
            
            var responseMessages = try await appState.mimoClient.sendMessage(
                sessionID: sessionID,
                parts: parts,
                options: sendOptions,
                parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel())
            )
            appState.scheduleGitRefresh(sessionID: sessionID)

            // Локальный агентский цикл для текстовых протоколов вызовов
            // (DSML / ```tool / Anthropic function_calls и т.п.): если сервер
            // вернул текст с вызовами без структурированных tool-инвокаций,
            // выполняем их ПОСЛЕДОВАТЕЛЬНО и отправляем результаты одним
            // ответом обратно модели.
            if let firstResponse = SessionSendLogic.assistantResponse(from: responseMessages),
               !(firstResponse.parts?.contains { part in
                   if case .toolInvocation = part { return true }
                   return false
               } ?? false) {
                var timelineParts: [MessagePartContent] = []
                let loopExecutor = ProjectWebToolExecutor.bridged(
                    projectRoot: appState.toolWorkingDirectory,
                    accessLevel: appState.accessLevel,
                    sessionId: sessionID
                )
                let loopResult = await AgentToolLoopLogic.run(
                    initialText: firstResponse.textContent,
                    execute: { call in
                        let result = await loopExecutor.execute(call)
                        // U5: тот же синхрон панели, что и в direct-цикле —
                        // серверный путь здесь не участвует.
                        if TodoPanelSyncLogic.updatesChecklist(toolName: call.name) {
                            let steps = TodoPanelSyncLogic.steps(
                                fromTodoItems: loopExecutor.loadTodoItems()
                            )
                            await MainActor.run {
                                self.appState.setSteps(steps, for: sessionID)
                                if !steps.isEmpty { self.appState.showGoal = true }
                            }
                        }
                        return result
                    },
                    emitToolCall: { call, result in
                        let argsText = call.arguments
                            .map { "\($0.key)=\($0.value)" }
                            .joined(separator: ", ")
                        timelineParts.append(.toolCall(
                            name: call.name, args: argsText,
                            result: result, callID: nil
                        ))
                        await MainActor.run {
                            self.publishToolParts(
                                AssistantTurnPartsLogic.directTimelineParts(
                                    timeline: timelineParts, answer: ""
                                ),
                                assistantID: assistantID
                            )
                        }
                    },
                    sendBack: { block in
                        let msgs = try await appState.mimoClient.sendMessage(
                            sessionID: sessionID,
                            parts: [["type": "text", "text": block]],
                            options: sendOptions,
                            parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel())
                        )
                        return SessionSendLogic.assistantResponse(from: msgs)?.textContent ?? ""
                    }
                )
                if loopResult.finalText != firstResponse.textContent || loopResult.iterationLimitReached {
                    let info = MimoMessageInfo(
                        id: nil, role: "assistant", agent: nil,
                        modelID: nil, providerID: nil, variant: nil, model: nil
                    )
                    responseMessages = [MimoMessageResponse(info: info, parts: [.text(loopResult.finalText)])]
                }
            }

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
                    self.syncExecutionSteps(from: merged.parts, sessionID: sessionID)
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
            await handleDirectSendError(
                error,
                assistantID: assistantID,
                retryCount: retryCount,
                sendSessionID: sendSessionID,
                selectedID: selectedID,
                messageID: messageID,
                text: text,
                files: files,
                images: images,
                agentModeOverride: agentModeOverride,
                route: route
            )
        }
    }
}
