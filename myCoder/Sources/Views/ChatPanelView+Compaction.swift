import SwiftUI
import AppKit

extension ChatPanelView {
    // MARK: - Context compaction (/compact + auto at 90%)

    /// Routes that send the local feed as history can be compacted; server-
    /// managed routes (mimo serve, opencode serve, web, ACP) keep their own
    /// history, so replacing it locally would be a lie. Per-role routing (M1)
    /// always composes each node's input from the LOCAL feed, so it compacts.
    func supportsLocalHistoryCompaction(_ route: SendRoute) -> Bool {
        if appState.modelRoutingConfiguration.mode == .perRole { return true }
        switch route {
        case .openAICompatible: return true
        default: return false
        }
    }

    /// Context window of the selected model: the provider metadata when it
    /// reports one, otherwise the catalog/default window. The badge and the
    /// auto-compaction threshold must use the SAME number as the model-switch
    /// decision — otherwise the chat compacts at the wrong moment.
    var selectedContextLimit: Int {
        // Читаем ревизию метаданных, чтобы SwiftUI пересчитал окно сразу
        // после правки параметров модели в настройках (C6).
        _ = appState.modelMetadataRevision
        return ContextBudgetLogic.effectiveContextLimit(
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID,
            serverProviders: appState.serverProviders
        )
    }

    /// Measured over the MODEL-BOUND history so the badge drops right after a
    /// compaction instead of showing the whole visible feed. `ContextBudgetLogic`
    /// counts the latest compiled payload once — each payload already contains
    /// the prior history (C6).
    var currentContextUsage: ContextUsage? {
        let history = ConversationCompactionLogic.historyForModel(messageStore.messages)
        guard !history.isEmpty else { return nil }
        return ContextBudgetLogic.usage(messages: history, limitTokens: selectedContextLimit)
    }

    func currentRoute() -> SendRoute {
        SendRouteResolver.route(
            selectedProviderID: appState.selectedProviderID,
            selectedModel: appState.effectiveSelectedModel(),
            serverConnected: appState.serverConnected,
            isACP: appState.isSelectedACPProvider,
            customProviders: appState.customProviders,
            localProviders: LocalProviderLogic.load(),
            webProviderIDs: appState.webProviderIDs
        )
    }

    /// Route-specific summarizer transport: a plain one-shot completion that
    /// never touches the visible chat (no streaming bubble, no tool protocol).
    /// In per-role routing mode the summary runs on the .compaction role's own
    /// model and is journalled like any other routed node (M1).
    func summaryTransport(for route: SendRoute, sessionID: String?) -> ConversationSummarizer.Transport {
        if appState.modelRoutingConfiguration.mode == .perRole {
            return routedCompactionTransport(sessionID: sessionID)
        }
        switch route {
        case .openAICompatible(let baseURL, let apiKey, let model):
            return { prompt in
                let result = try await DirectChatClient.send(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: [DirectChatMessage(role: "user", content: prompt)],
                    transport: URLSessionDirectChatTransport(
                        timeout: ConversationCompactionLogic.summaryRequestTimeout
                    )
                )
                return result.content
            }
        default:
            return { _ in throw ConversationSummarizerError.nothingToCompact }
        }
    }

    /// Replace the model-bound history with a factual summary message. The
    /// full chat stays visible; `historyForModel` cuts at the newest summary.
    ///
    /// The outcome is a value, not a chat message: the model-switch flow
    /// needs to know whether the history was touched (to offer a rollback) or
    /// not (a stopped compaction changes nothing).
    @MainActor
    func performCompaction(
        reason: String,
        sessionID: String? = nil
    ) async -> ConversationCompactionOutcome {
        guard !isCompacting else {
            return .failed("A compaction is already running.")
        }
        let targetSessionID = sessionID ?? messageStore.currentSessionID
        let history = ConversationCompactionLogic.historyForModel(
            messageStore.messages(in: targetSessionID)
        )
        guard ConversationCompactionLogic.plan(messages: history) != nil else {
            return .nothingToCompact
        }
        let route = currentRoute()
        guard supportsLocalHistoryCompaction(route) else {
            return .unsupported("Compaction is not available for this provider: its history is kept on the server (mimo/opencode serve, web or ACP), so a local summary would not shrink it.")
        }
        isCompacting = true
        defer { isCompacting = false }

        let beforeTokens = ContextBudgetLogic.usedTokens(messages: history)
        let summarizer = ConversationSummarizer(transport: summaryTransport(for: route, sessionID: targetSessionID))
        do {
            // The summary request goes to the model that will continue the
            // chat, so the transcript must fit into ITS window: a 48k
            // character transcript does not fit an 8k model.
            let transcriptBudget = ConversationCompactionLogic.summaryTranscriptBudget(
                contextWindowTokens: selectedContextLimit
            )
            let summary = try await summarizer.summarize(
                messages: history,
                maxCharacters: transcriptBudget
            )
            // The user may have stopped the compaction while the summary was
            // being produced: nothing may be appended then.
            try Task.checkCancellation()
            let summaryMessage = ConversationCompactionLogic.summaryMessage(summary: summary)
            messageStore.append(summaryMessage, to: targetSessionID)
            let afterTokens = ContextUsageLogic.estimateTokens(summary)
            let note = Message(
                role: .assistant,
                content: "Context compacted (\(reason)): \(history.count) messages summarized, ~\(ContextUsageLogic.formatTokens(beforeTokens)) → ~\(ContextUsageLogic.formatTokens(afterTokens)) tokens. The full chat stays visible; the model now continues from the summary.",
                isFinished: true
            )
            messageStore.append(note, to: targetSessionID)
            return .compacted(
                summaryMessageID: summaryMessage.id,
                noticeMessageID: note.id,
                beforeTokens: beforeTokens,
                afterTokens: afterTokens
            )
        } catch is CancellationError {
            // The history is untouched: the summary was never appended.
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Manual compaction (`/compact`): the outcome is reported in the chat.
    @MainActor
    func compactConversation(reason: String, sessionID: String? = nil) async {
        guard !isCompacting else { return }
        let targetSessionID = sessionID ?? messageStore.currentSessionID
        let outcome = await performCompaction(reason: reason, sessionID: targetSessionID)
        switch outcome {
        case .compacted:
            // The "context compacted" note is already in the feed.
            break
        case .cancelled:
            messageStore.append(Message(
                role: .assistant,
                content: "Context compaction stopped — the history is unchanged.",
                isFinished: true
            ), to: targetSessionID)
        case .failed(let message):
            messageStore.append(Message(
                role: .assistant,
                content: "Context compaction failed: \(message)",
                isFinished: true
            ), to: targetSessionID)
        case .unsupported(let message):
            messageStore.append(Message(
                role: .assistant,
                content: message,
                isFinished: true
            ), to: targetSessionID)
        case .nothingToCompact:
            messageStore.append(Message(
                role: .assistant,
                content: ConversationSummarizerError.nothingToCompact.errorDescription ?? "Nothing to compact.",
                isFinished: true
            ), to: targetSessionID)
        }
    }

    /// Auto-compaction trigger (plan: 90% of the window). Runs before the
    /// outgoing history is built; failures never block the send.
    @MainActor
    func autoCompactIfNeeded(route: SendRoute, sessionID: String?) async {
        guard supportsLocalHistoryCompaction(route) else { return }
        let history = ConversationCompactionLogic.historyForModel(
            messageStore.messages(in: sessionID)
        )
        guard !history.isEmpty else { return }
        let usage = ContextBudgetLogic.usage(messages: history, limitTokens: selectedContextLimit)
        guard ContextUsageLogic.shouldCompact(usage) else { return }
        await compactConversation(reason: "auto at \(usage.percent)%", sessionID: sessionID)
    }

    // MARK: - Model switch compaction

    /// Model switch into a smaller context window: the chat is compacted
    /// BEFORE it continues (user directive 2026-11-08). The user keeps
    /// control — the compaction can be stopped, rolled back, or replaced by
    /// another model with a larger window.
    @MainActor
    func handleModelSwitch(to newModel: String) {
        let previousModel = lastSelectedModel
        lastSelectedModel = newModel
        guard !newModel.isEmpty else { return }

        let sessionID = messageStore.currentSessionID
        let history = ConversationCompactionLogic.historyForModel(
            messageStore.messages(in: sessionID)
        )
        let usedTokens = ContextBudgetLogic.usedTokens(messages: history)
        let limitTokens = ContextBudgetLogic.effectiveContextLimit(
            modelID: newModel,
            providerID: appState.selectedProviderID,
            serverProviders: appState.serverProviders
        )
        // The candidates are collected only when a compaction is really
        // needed: the scan walks every provider and every model.
        let candidates = ModelSwitchCompactionLogic.requiresCompaction(
            previousModel: previousModel,
            usedTokens: usedTokens,
            limitTokens: limitTokens
        ) ? appState.modelSwitchCompactionCandidates : []
        guard let notice = ModelSwitchCompactionLogic.notice(
            previousModel: previousModel,
            newModel: newModel,
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            candidates: candidates,
            sessionID: sessionID
        ) else {
            // The chat fits into the new window: nothing has to be compacted.
            stopRunningModelSwitchCompaction(clearNotice: true)
            return
        }
        appState.modelSwitchCompactionNotice = notice
        startModelSwitchCompaction(notice: notice)
    }

    /// Start the automatic compaction that follows a model switch.
    @MainActor
    func startModelSwitchCompaction(notice: ModelSwitchCompactionNotice) {
        modelSwitchCompactionTask?.cancel()
        modelSwitchCompactionGeneration += 1
        let generation = modelSwitchCompactionGeneration
        var running = notice
        running.phase = .running
        appState.modelSwitchCompactionNotice = running
        modelSwitchCompactionTask = Task { @MainActor in
            let outcome = await performCompaction(
                reason: "model switch to \(notice.newModel)",
                sessionID: notice.sessionID
            )
            applyModelSwitchCompactionOutcome(outcome, notice: notice, generation: generation)
            if modelSwitchCompactionGeneration == generation {
                modelSwitchCompactionTask = nil
            }
        }
    }

    /// Apply the result of a compaction to the visible notice. A stale task
    /// (a retry, another chat) never overwrites a newer notice.
    @MainActor
    func applyModelSwitchCompactionOutcome(
        _ outcome: ConversationCompactionOutcome,
        notice: ModelSwitchCompactionNotice,
        generation: Int
    ) {
        guard generation == modelSwitchCompactionGeneration else { return }
        guard var current = appState.modelSwitchCompactionNotice,
              current.newModel == notice.newModel,
              current.sessionID == notice.sessionID else { return }
        current.phase = ModelSwitchCompactionLogic.phase(for: outcome)
        switch outcome {
        case .compacted(let summaryID, let noticeID, _, _):
            current.summaryMessageID = summaryID
            current.noticeMessageID = noticeID
            current.error = nil
            current.retryable = true
        case .failed(let message):
            current.error = message
            current.retryable = true
        case .unsupported(let message):
            current.error = message
            // The provider keeps the history on the server: running it again
            // would fail the same way, so the retry button is pointless.
            current.retryable = false
        case .cancelled:
            current.error = nil
            current.retryable = true
        case .nothingToCompact:
            current.error = "There is nothing to compact."
            current.retryable = true
        }
        appState.modelSwitchCompactionNotice = current
    }

    /// Stop a running model-switch compaction. `clearNotice` also drops the
    /// banner — used when the new model fits and there is nothing to say.
    @MainActor
    func stopRunningModelSwitchCompaction(clearNotice: Bool) {
        if modelSwitchCompactionTask != nil {
            modelSwitchCompactionTask?.cancel()
            modelSwitchCompactionTask = nil
            modelSwitchCompactionGeneration += 1
        }
        guard clearNotice else { return }
        if appState.modelSwitchCompactionNotice?.phase == .compacted {
            // The chat really was compacted — keep the banner so the user can
            // still roll it back.
            return
        }
        appState.modelSwitchCompactionNotice = nil
    }

    /// Stop the compaction: the history stays exactly as it was.
    @MainActor
    func stopModelSwitchCompaction() {
        modelSwitchCompactionTask?.cancel()
        modelSwitchCompactionTask = nil
        modelSwitchCompactionGeneration += 1
        guard var notice = appState.modelSwitchCompactionNotice else { return }
        notice.phase = .cancelled
        appState.modelSwitchCompactionNotice = notice
    }

    /// Roll the compaction back: the appended summary and note are removed,
    /// so the model sees the full history again.
    @MainActor
    func rollbackModelSwitchCompaction() {
        guard var notice = appState.modelSwitchCompactionNotice else { return }
        let targets = ModelSwitchCompactionLogic.rollbackTargets(
            summaryMessageID: notice.summaryMessageID,
            noticeMessageID: notice.noticeMessageID
        )
        for target in targets {
            messageStore.remove(id: target)
        }
        notice.phase = .rolledBack
        notice.summaryMessageID = nil
        notice.noticeMessageID = nil
        appState.modelSwitchCompactionNotice = notice
    }

    /// Compact again after a stop, a failure or a rollback.
    @MainActor
    func retryModelSwitchCompaction() {
        guard let notice = appState.modelSwitchCompactionNotice else { return }
        startModelSwitchCompaction(notice: notice)
    }

    /// Switch to a model with a larger context window instead of compacting.
    ///
    /// The bigger window often lives in another provider, so the provider is
    /// switched first and the model second: `selectModel` only accepts a model
    /// of the currently selected provider.
    @MainActor
    func chooseLargerModel(_ candidate: ModelSwitchCompactionLogic.Candidate) {
        // The chat fits into the new window — the compaction is not needed.
        stopRunningModelSwitchCompaction(clearNotice: true)
        if candidate.providerID != appState.selectedProviderID {
            appState.selectProvider(candidate.providerID)
        }
        appState.selectModel(candidate.id)
    }

    /// Hide the banner without touching the history. A running compaction is
    /// stopped first — otherwise the summary would land in the chat after the
    /// user closed the notice.
    @MainActor
    func dismissModelSwitchCompactionNotice() {
        if appState.modelSwitchCompactionNotice?.canStop == true {
            stopModelSwitchCompaction()
        }
        appState.modelSwitchCompactionNotice = nil
    }

    /// Wait for the automatic compaction that follows a model switch: the turn
    /// must not be built from a history that is about to be replaced.
    @MainActor
    func awaitModelSwitchCompactionIfNeeded() async {
        guard let notice = appState.modelSwitchCompactionNotice,
              ModelSwitchCompactionLogic.blocksSend(phase: notice.phase) else { return }
        await modelSwitchCompactionTask?.value
    }
}
