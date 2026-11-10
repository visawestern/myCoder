import SwiftUI
import AppKit

extension ChatPanelView {
    func sendDirectly(
        text: String,
        files: [FileInfo],
        images: [ClipboardImage] = [],
        agentModeOverride: AgentMode? = nil,
        retryCount: Int = 0,
        retryPlan: SessionBusyRetryLogic.RetryPlan? = nil,
        existingUserMessageID: String? = nil,
        sessionID explicitSessionID: String? = nil,
        qualityGateDepth: Int = 0,
        goalVerifyDepth: Int = 0
    ) async {
        let gateSessionID = explicitSessionID
            ?? retryPlan?.sessionID
            ?? appState.selectedSession?.id
        if AnswerQualityGate.userOrderedNoStop(in: text) {
            NoStopOrderStore.setOrdered(sessionID: gateSessionID ?? "")
        }
        await performDirectSend(
            text: text,
            files: files,
            images: images,
            agentModeOverride: agentModeOverride,
            retryCount: retryCount,
            retryPlan: retryPlan,
            existingUserMessageID: existingUserMessageID,
            sessionID: explicitSessionID
        )
        await runAnswerQualityGate(sessionID: gateSessionID, request: text, depth: qualityGateDepth)
        await runGoalVerification(sessionID: gateSessionID, noProgressCount: goalVerifyDepth)
    }

    /// The post-turn devil's-advocate review. Honest by construction: an
    /// unfinished turn, a finished plan, a missing internal model or an
    /// unparsable verdict all SKIP the gate instead of inventing a score.
    func runAnswerQualityGate(sessionID: String?, request: String, depth: Int) async {
        guard depth < AnswerQualityGate.maxAutoContinues else { return }
        guard let sessionID, !sessionID.isEmpty else { return }
        // The turn must be fully finished: streaming or an unanswered plan
        // question is an unfinished turn, the gate has nothing to review.
        let turn = await MainActor.run { () -> (answer: String, projectRoot: String?)? in
            guard !appState.isStreaming,
                  appState.pendingQuestionRequest?.sessionID != sessionID else { return nil }
            let messages = messageStore.messages(in: sessionID)
            guard let last = messages.last(where: {
                $0.role == .assistant && $0.isFinished && !$0.content.isEmpty
            }), !last.content.hasPrefix("Error:") else { return nil }
            return (last.content, appState.selectedWorkspace?.path)
        }
        guard let turn else { return }
        let planItems = turn.projectRoot.map { PlanTodoBridge.planItems(projectPath: $0) } ?? []
        guard !AnswerQualityGate.planIsComplete(items: planItems) else { return }

        let outcome = await AnswerQualityGateRunner.evaluate(
            request: request,
            answer: turn.answer,
            planItems: planItems,
            noStopOrdered: NoStopOrderStore.isOrdered(sessionID: sessionID)
        )
        if let verdict = outcome.verdict {
            let note = AnswerQualityGate.note(for: verdict, decision: outcome.decision)
            await MainActor.run {
                messageStore.append(
                    Message(id: UUID().uuidString, role: .system, content: note, isStreaming: false),
                    to: sessionID
                )
            }
        }
        if case .continueTurn(let feedback) = outcome.decision {
            await sendDirectly(
                text: feedback,
                files: [],
                agentModeOverride: nil,
                sessionID: sessionID,
                qualityGateDepth: depth + 1
            )
        }
    }

    /// Post-turn ЦЕЛЬ auto-verification. After the assistant's answer is
    /// complete, an internal model acts as devil's advocate and checks whether
    /// the active goal's plan steps are REALLY done. When not complete, a
    /// continuation prompt («продолжай по плану, обнови прогресс») is injected
    /// and the turn auto-continues. When complete, the goal is marked done.
    /// Honest by construction: no active goal, an unfinished turn, or a
    /// missing internal model all skip quietly instead of inventing a verdict.
    ///
    /// `noProgressCount` — число БЕЗРЕЗУЛЬТАТНЫХ продолжений подряд (после
    /// них план не изменился: модель буксует). Лимит применяется только к
    /// ним; пока план движется (появляются done-шаги), счётчик сбрасывается
    /// и авто-цикл идёт до выполнения (директива 2026-11-09).
    func runGoalVerification(sessionID: String?, noProgressCount: Int) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let session = await MainActor.run { () -> ChatSession? in
            guard let sessionID,
                  let session = appState.sessions.first(where: { $0.id == sessionID }) else {
                return nil
            }
            return session
        }
        let context = await MainActor.run {
            GoalContextLogic.context(
                chatID: sessionID,
                sessionDirectory: session?.directory,
                selectedWorkspacePath: appState.selectedWorkspace?.path
            )
        }
        let goals = GoalContextLogic.visibleGoals(
            GoalStore.load(homeDirectory: home),
            context: context
        )

        // The turn must be fully finished: an unfinished turn has no final
        // answer to verify.
        let turn = await MainActor.run { () -> (answer: String, isError: Bool)? in
            guard !appState.isStreaming,
                  appState.pendingQuestionRequest?.sessionID != sessionID else { return nil }
            let messages = sessionID.flatMap { messageStore.messages(in: $0) } ?? []
            guard let last = messages.last(where: {
                $0.role == .assistant && $0.isFinished && !$0.content.isEmpty
            }) else { return nil }
            return (last.content, GoalCyclePolicy.isFailedTurn(answer: last.content))
        }
        guard let turn else { return }

        // Ошибочный ответ модели (503/401 и т.п.) — единственная
        // «безрезультатная попытка», к которой применяется лимит 5
        // (директива 2026-11-09). Нормальный ответ модели никогда не
        // приближает к остановке — даже если план не изменился.
        if turn.isError {
            let next = GoalCyclePolicy.failure(afterFailureCount: noProgressCount)
            if GoalCyclePolicy.shouldStopAfterNoProgress(failureCount: next) {
                await pauseGoalForStall(sessionID: sessionID, goals: goals, home: home)
            } else {
                await sendDirectly(
                    text: GoalVerificationPromptBuilder.continuationMessage(language: appState.appLanguage),
                    files: [],
                    agentModeOverride: nil,
                    sessionID: sessionID,
                    goalVerifyDepth: next
                )
            }
            return
        }

        guard let goal = goals.first(where: { $0.state == .active }),
              !GoalPlanStatusLogic.isComplete(goal.plan) else { return }

        let service = GoalVerificationService { system, user in
            try await InternalModelRunner.complete(messages: [
                DirectChatMessage(role: "system", content: system),
                DirectChatMessage(role: "user", content: user),
            ])
        }
        let outcome = await service.verify(
            goal: goal, lastAssistantText: turn.answer, language: appState.appLanguage)

        // Помечаем прогресс: план обновляется по вердикту (done для
        // подтверждённых шагов, in_progress для текущих).
        let updatedPlan = GoalRunner.updatedPlan(goal.plan, verdict: outcome.verdict)
        let progressed = GoalCyclePolicy.progressed(from: goal.plan, to: updatedPlan)
        _ = try? GoalStore.updatePlan(id: goal.id, plan: updatedPlan, homeDirectory: home)
        NotificationCenter.default.post(name: Notification.Name("myCoderGoalStoreChanged"), object: nil)

        // Вердикт complete закрывает цель ВСЕГДА — независимо от счётчика
        // безрезультатных попыток: последнее слово за моделью, а не за
        // лимитом. Именно этот путь молча убивался старым guard'ом в начале
        // функции (live-дефект 2026-11-09: dflash-анализ завершился вердиктом
        // complete, но цель встала на паузу «лимит исчерпан»).
        if outcome.verdict.complete {
            _ = try? GoalStore.setState(id: goal.id, state: .done, homeDirectory: home)
            await MainActor.run {
                if let sessionID {
                    messageStore.append(
                        Message(id: UUID().uuidString, role: .system,
                                content: "🎯 Цель выполнена: \(goal.title)",
                                isStreaming: false),
                        to: sessionID)
                }
            }
            return
        }

        // Not complete → status note + auto-continue with the continuation prompt.
        guard let continuation = outcome.continuation else { return }
        await MainActor.run {
            if let sessionID {
                messageStore.append(
                    Message(id: UUID().uuidString, role: .system,
                            content: "🎯 \(goal.title): \(outcome.verdict.reason)",
                            isStreaming: false),
                    to: sessionID)
            }
        }
        // Нормальный ответ модели — не «безрезультатная попытка»: счётчик
        // сбрасывается при прогрессе, иначе остаётся как есть. Лимит НЕ
        // растёт из-за того, что план не изменился (модель может работать
        // напрямую, без todo_шагов).
        let nextCount = progressed
            ? GoalCyclePolicy.success(afterFailureCount: noProgressCount)
            : noProgressCount
        await sendDirectly(
            text: continuation,
            files: [],
            agentModeOverride: nil,
            sessionID: sessionID,
            goalVerifyDepth: nextCount
        )
    }

    /// Поставить активную цель на паузу с причиной стагнации (лимит 5
    /// безрезультатных попыток подряд — ошибочные ответы модели — исчерпан).
    func pauseGoalForStall(sessionID: String?, goals: [UserGoal], home: URL) async {
        guard let goal = goals.first(where: { $0.state == .active }) else { return }
        _ = try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: home)
        _ = try? GoalStore.setLastError(id: goal.id, error: GoalCyclePolicy.stallReason, homeDirectory: home)
        let chatID = goal.chatID ?? sessionID
        await MainActor.run {
            if let chatID {
                messageStore.append(
                    Message(id: UUID().uuidString, role: .system,
                            content: "🎯 \(goal.title): \(GoalCyclePolicy.stallReason)",
                            isStreaming: false),
                    to: chatID)
            }
        }
    }

    /// Direct OpenAI-compatible turn with real token streaming. The answer is
    /// written into its own chat's feed as it arrives, so switching chats no
    /// longer hides the text until the whole response is ready. Providers that
    /// reject `stream: true` fall back to the plain request.
    // (streamDirectChat / startServeTimeout moved to ChatPanelView+ToolLoop.swift — audit B3)

    /// One assistant message can have several gated calls. They are all
    /// registered and rendered before the loop starts awaiting them, so the
    /// user sees the full queue instead of one modal at a time.

    /// M1: executes the whole per-role route graph for one send and writes the
    /// honest outcome into the assistant message: final text per status, node
    /// journal, aggregated usage, per-node route chips and raw responses.
    ///
    /// Вход: id assistant-сообщения, id чата, собранный запрос, вложения, режим.
    /// Выход: нет (обновляет messageStore/appState; прогресс каждого узла виден
    /// в пузыре сообщения, отмена родительского хода отменяет все узлы).
    /// Зависимости: `buildRoutedTurnSnapshot`, `RoutedTurnExecutor`,
    /// `AppState.recordRouteJournalEntry`, `ToolProtocolStripping`.
    func runRoutedTurn(
        assistantID: String,
        sendSessionID: String?,
        request: String,
        files: [FileInfo],
        images: [ClipboardImage],
        agentMode: AgentMode
    ) async {
        let snapshot = await MainActor.run {
            buildRoutedTurnSnapshot(
                sessionID: sendSessionID,
                request: request,
                agentMode: agentMode,
                files: files,
                images: images
            )
        }
        // The graph runs inside this Task: cancelling the turn (Stop) cancels
        // the task and therefore every pending node — the runner checks
        // cancellation before and after each role.
        let outcome = await RoutedTurnExecutor.run(snapshot: snapshot) { role, assignment in
            Task { @MainActor in
                guard self.currentAssistantMessageID == assistantID else { return }
                let line = "⚙️ \(role.displayName) → \(assignment.providerID)/\(assignment.modelID)…"
                self.streamingText = line
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = line
                }
            }
        }
        await MainActor.run {
            // The journal records EVERY node that ran — including failed and
            // cancelled ones — before the message shows the final state.
            for entry in outcome.entries {
                appState.recordRouteJournalEntry(entry)
            }
            appState.isLoading = false
            appState.isStreaming = false
            streamingText = ""
            messageStore.update(id: assistantID) { msg in
                switch outcome.status {
                case .completed:
                    msg.content = ToolProtocolStripping.visibleText(from: outcome.finalText ?? "")
                case .reviewLimitReached:
                    // Visible degradation: findings + last draft, never a fake
                    // "complete" answer.
                    msg.content = outcome.finalText ?? ""
                case .cancelled:
                    let kept = ToolProtocolStripping.visibleText(from: msg.content)
                    msg.content = kept.hasPrefix("⚙️") || kept.isEmpty
                        ? L.t(AppLocalizationKey.locGenerationStopped)
                        : kept
                case .failed(let message):
                    msg.content = message
                }
                msg.usage = outcome.usage
                msg.rawResponses = outcome.rawResponses
                var routeParts = msg.parts
                routeParts.removeAll { if case .routeInfo = $0 { return true } else { return false } }
                if !outcome.chips.isEmpty {
                    routeParts.append(.routeInfo(chips: outcome.chips))
                }
                msg.parts = routeParts
                msg.isFinished = true
                msg.isStreaming = false
            }
            currentAssistantMessageID = nil
        }
    }
}
