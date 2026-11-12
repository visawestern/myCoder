import SwiftUI
import AppKit

extension ChatPanelView {
    /// Builds `[ACPRequestMessage]` from the user's text, file references and
    /// images. Uses ACPMessageBuilder so real image bytes (data URLs) are sent
    /// instead of a "[N image(s) attached]" placeholder (plan Раздел 9 Блок 2).
    /// Run one turn against a web provider through the AntiBrowser cast + WebChatDriver, presenting events (streaming/tool/captcha/final)
    /// into the chat so the message actually reaches the web model and shows a
    /// real response (plan Раздел 12). The login lives in the persistent
    /// AntiBrowser profile, so no cookie files are restored here.
    @MainActor
    func runWebChatTurn(config: WebProviderConfig,
                                text: String,
                                assistantID: String,
                                chatID: String,
                                preparedSystemPrompt: String? = nil) async {
        // Reconcile selections created before the unified web-selection contract
        // existed. The browser must use the same model and effort the composer
        // shows, even for an old config saved by a previous build.
        var effectiveConfig = config
        let availableModels = WebProviderConnectivity.models(for: config)
        let routedWebModel = appState.effectiveSelectedModel()
        effectiveConfig.selectedModel = availableModels.contains(routedWebModel)
            ? routedWebModel
            : WebProviderSelectionLogic.effectiveSelectedModel(
                for: config,
                availableModels: availableModels
            )
        effectiveConfig.effort = appState.selectedWebEffort ?? .medium
        if effectiveConfig != config {
            WebProviderStore.save(WebProviderStore.upsert(effectiveConfig, in: WebProviderStore.load()))
        }
        activeWebProviderID = effectiveConfig.id

        // AntiBrowser: один движок, одна вкладка на чат. Повторный вход в
        // тот же чат переиспользует запомненную вкладку браузера.
        let projectID = appState.selectedWorkspace?.id ?? appState.selectedWorkspace?.path ?? "global"
        let refreshKey = "\(effectiveConfig.id)|\(projectID)|\(chatID)"
        webCatalogRefreshKeys.remove(refreshKey)

        do {
            try EngineStatusCenter.shared.requireEngine()
        } catch {
            appendWebStatus(to: assistantID, line: error.localizedDescription)
            messageStore.update(id: assistantID) { m in
                m.content = error.localizedDescription
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }
        let tabKey = AntiBrowserTabManager.makeKey(providerID: effectiveConfig.id,
                                                  projectID: projectID,
                                                  chatID: chatID)
        let bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        // Показываем мини-каст вкладки этого чата внутри приложения.
        appState.showWebBrowserPanel(for: effectiveConfig, projectID: projectID, chatID: chatID)
        // Resolve vendor-specific selectors from the catalog.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: effectiveConfig.vendor.id)
        let selectors = WebVendorSelectors(
            input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
            sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='end'], button[data-testid='send-button'], .send-button-container",
            responseContainer: catalogEntry?.responseContainer ?? "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: catalogEntry?.stopButton ?? ".send-button-container.stop, button[aria-label*='top'], button[data-testid='stop-button'], button[class*='stop']"
        )

        // AntiBrowser keeps the login in its persistent profile; the tab is
        // already authenticated from the login screen. No cookie files exist.
        do {
            // Audit 2026-09-08/09: host-only matching kept turns running on
            // the wrong PRODUCT surface. Require the surface matching the
            // selected model (Kimi K3/K3 Swarm live on /agent — navigating
            // "back" to the chat URL resets the choice to Fast and blocks
            // the send; plain chat models must NOT sit on /agent).
            let currentURL = (try? await bridge.currentURL()) ?? ""
            let onChatSurface = !currentURL.isEmpty && WebChatSurfaceLogic.isChatSurface(
                urlString: currentURL,
                chatURL: effectiveConfig.chatURL,
                vendor: effectiveConfig.vendor,
                selectedModel: effectiveConfig.selectedModel
            )
            if !onChatSurface {
                // Kimi agent models (K3/K3 Swarm) live on /agent: a fresh or
                // drifted webview must land THERE, not on the plain chat URL
                // (which would reset the choice to Fast).
                try await bridge.navigate(to: WebChatSurfaceLogic.targetSurfaceURL(
                    chatURL: effectiveConfig.chatURL,
                    vendor: effectiveConfig.vendor,
                    selectedModel: effectiveConfig.selectedModel
                ))
            }
            // Wait for chat interface to be ready (input element present).
            // Some sites need extra time to hydrate the chat UI after login.
            var ready = false
            for _ in 0..<30 {
                if (try? await bridge.exists(selector: selectors.input)) ?? false {
                    ready = true
                    break
                }
                await bridge.wait(ms: 500)
            }
            if !ready {
                appendWebStatus(to: assistantID, line: "Chat input not found — page may need manual login.")
            }
        } catch {
            messageStore.update(id: assistantID) { m in
                m.content = "Could not open \(effectiveConfig.chatURL): \(error.localizedDescription). Check that the site is reachable and you are logged in."
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }

        // SmartSend fallback: try direct API or smart element detection first
        // AFTER the page is loaded and ready. If it succeeds, the message was
        // already sent, so we skip the standard driver.runTurn() typing/clicking
        // but still need to wait for the response.
        // Round 30b: capture the response fingerprint BEFORE submitting — the
        // answer may be fully rendered by the time the driver reads its
        // baseline (binding + injection take seconds), and a post-send baseline
        // would make awaitResponse wait for changes that never come.
        let preSendFingerprint = (try? await bridge.responseFingerprint(selector: selectors.responseContainer)) ?? ""
        // Audit 2026-09-08: SmartSend submits the RAW user text, but on the
        // FIRST turn of a mapped conversation the tool-protocol preamble MUST
        // reach the model — without it live models answer "I have no file
        // access" (Qwen evidence) and the agent loop never starts. Prepend the
        // same preamble runTurn would have used; runTurn receives skipSend and
        // will not duplicate it.
        let smartSendWorkspacePath = appState.toolWorkingDirectory
        let webTurnSystemPrompt = preparedSystemPrompt ?? WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: effectiveConfig.systemPrompt,
            projectRoot: smartSendWorkspacePath,
            directory: smartSendWorkspacePath,
            isGitRepo: (try? GitRepository.repositoryRoot(for: smartSendWorkspacePath)) != nil
        )
        let smartSendMessage = TurnDelivery.withSystem(webTurnSystemPrompt, modelText: text)
        let smartSendResult = await trySmartSendFallback(
            config: effectiveConfig, bridge: bridge, message: smartSendMessage
        )
        let skipDriverSend = smartSendResult.success
        if smartSendResult.success {
            appendWebStatus(to: assistantID, line: "Sent via \(smartSendResult.winningMethod ?? "smart-fallback"), waiting for response…")
        }

        // Round 8 P4: give immediate visible feedback while the page loads and
        // the first turn is sent (the old flow left an empty bubble).
        messageStore.update(id: assistantID) { m in
            if m.content.isEmpty {
                let model = effectiveConfig.selectedModel.isEmpty ? effectiveConfig.displayName : effectiveConfig.selectedModel
                m.content = SendStatusText.thinkingPlaceholder(modelID: model)
            }
        }

        // Do not open the model dropdown during send. Model discovery is an
        // explicit user action in the settings sheet; opening it here can leave
        // the page menu mounted and make an effort control look like the model.
        // The driver now applies only the persisted modelButton and effortDropdown.

        // E09/E10: real tool operations feed the project's undo stack and
        // request_history — pass the per-project undo manager + session so
        // write/edit tool calls snapshot, record undo entries and history rows.
        // E12: run_command executes only at .fullAccess (gate enforced here).
        let workspacePath = appState.toolWorkingDirectory
        // Shared approval mailbox: the driver posts requests here and blocks
        // in awaitAnswer until the user resolves the Allow/Deny card.
        let approvalBox = WebToolApprovalBox()
        activeApprovalBox = approvalBox
        var executor = ProjectWebToolExecutor(
            projectRoot: workspacePath,
            undoManager: (try? ProjectUndoManager(projectPath: workspacePath)),
            sessionId: messageStore.currentSessionID,
            messageId: assistantID,
            accessLevel: appState.accessLevel,
            isProjectless: ProjectlessWorkspaceLogic.isProjectless(
                sessionDirectory: appState.selectedSession?.directory
            )
        )
        executor.projectlessWritePrompt = { suggested in
            await self.promptCreateProjectForFileWrite(
                suggestedName: suggested,
                sessionID: messageStore.currentSessionID
            )
        }
        executor.bridge = bridge
        executor.selectors = selectors
        let driver = WebChatDriver(bridge: bridge, executor: executor, selectors: selectors,
                                   config: effectiveConfig, projectRoot: workspacePath, accessLevel: appState.accessLevel,
                                   approvalBox: approvalBox, preparedSystemPrompt: webTurnSystemPrompt)

        // Whether this local chat ever started a remote session — must be
        // known BEFORE binding: a first turn must open a genuinely fresh
        // remote chat, never land in the currently-open conversation.
        let preBindKey = appState.webRemoteChatKey(for: effectiveConfig,
                                                   projectID: projectID,
                                                   chatID: chatID)
        let isFirstTurnForBinding = appState.webSessionIsFirstTurn(preBindKey)
        let remoteMapping: WebRemoteChatMapping?
        do {
            remoteMapping = try await bindWebRemoteChat(driver: driver,
                                                        bridge: bridge,
                                                        config: effectiveConfig,
                                                        projectID: projectID,
                                                        chatID: chatID,
                                                        freshSubmitPending: skipDriverSend,
                                                        isFirstTurn: isFirstTurnForBinding)
        } catch {
            appState.recordWebBrowserAction(action: "remote_chat_binding_failed",
                                            config: effectiveConfig,
                                            projectID: projectID,
                                            chatID: chatID,
                                            modelID: effectiveConfig.selectedModel,
                                            effort: appState.selectedWebEffort,
                                            detail: error.localizedDescription)
            messageStore.update(id: assistantID) { m in
                m.content = "Web chat was not sent: \(error.localizedDescription)"
                m.isFinished = true
                m.isStreaming = false
            }
            finishWebTurn()
            return
        }
        appState.recordWebBrowserAction(action: "send_started",
                                        config: effectiveConfig,
                                        projectID: projectID,
                                        chatID: chatID,
                                        modelID: effectiveConfig.selectedModel,
                                        effort: appState.selectedWebEffort,
                                        remoteChatID: remoteMapping?.remoteChatID,
                                        detail: remoteMapping == nil
                                            ? "AntiBrowser background send; remote chat id will be bound after the first message lands (SPA vendor)"
                                            : "AntiBrowser background send bound to verified remote chat")

        // Send the tool-protocol preamble only on the first mapped conversation;
        // later turns continue exactly that remote conversation.
        let bindingKey = remoteMapping?.key ?? appState.webRemoteChatKey(for: effectiveConfig,
                                                                         projectID: projectID,
                                                                         chatID: chatID)
        let isFirst = appState.webSessionIsFirstTurn(bindingKey)
        appState.markWebSessionStarted(bindingKey)
        let retrySignal = WebChatRetrySignal()
        let approvalSignal = WebChatApprovalSignal()
        let completionSignal = WebChatCompletionSignal()
        // Live tool-call parts for THIS assistant message: each toolCall event
        // appends a part (result == nil → running); the matching toolResult
        // fills it in. The final answer lands in m.content, so spoilers and
        // answer text never overwrite each other.
        let toolPartsBox = WebToolPartsBox()
        // User directive 2026-09-11: NOTHING the model produced may be wiped
        // from the chat. Kimi streams "thinking" prose first, then the answer;
        // tool rounds produce an answer after each round. Every accepted
        // text snapshot is kept in the accumulator and displayed as
        // previous-content + latest snapshot, so early reasoning survives.
        let textAccumulator = WebTurnTextAccumulator()
        let presentEvent: (WebChatEvent) -> Void = { event in
            completionSignal.recordIfCompleted(event)
            if case .approvalRequired(_, let message) = event {
                approvalSignal.record(message)
            }
            if let reason = self.webCatalogRefreshReason(for: event) {
                retrySignal.record(reason)
            }
            switch event {
            case .toolCall(let call):
                MyCoderAPIServer.appendLog("🧰 web toolCall: \(call.name) args=\(call.arguments)")
            case .toolResult(let name, let result):
                MyCoderAPIServer.appendLog("🧰 web toolResult: \(name) len=\(result.count)")
            default:
                break
            }
            Task { @MainActor in
                let presentation = WebChatEventPresenter.present(event)
                switch WebCaptchaPresentationLogic.action(for: event) {
                case .showSolver:
                    if case .captcha(_, let note) = presentation {
                        self.captchaSolverContext = WebCaptchaSolverContext(bridge: bridge, note: note)
                    }
                case .dismissSolver:
                    self.captchaSolverContext = nil
                case .none:
                    break
                }
                switch event {
                case .streaming(let text):
                    // Live partial answer: APPEND to everything the model has
                    // produced this turn (user directive 2026-09-11: never
                    // erase earlier thinking/answers) — a growing snapshot of
                    // the SAME message extends it, a NEW message after tool
                    // rounds starts a fresh block. Tool spoilers persist.
                    let merged = textAccumulator.absorb(text)
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.content = merged
                        m.isStreaming = true
                        if !toolParts.isEmpty { m.parts = toolParts }
                    }
                case .toolCall(let call):
                    // A tool round finished: close the current text block so
                    // the post-tool answer does not graft onto it.
                    textAccumulator.closeBlock()
                    let partID = UUID().uuidString
                    toolPartsBox.appendRunning(
                        name: call.name,
                        args: call.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                        partID: partID
                    )
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.parts = toolParts
                        m.isStreaming = true
                    }
                case .toolResult(let name, let result):
                    toolPartsBox.completeLast(name: name, result: result)
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        m.parts = toolParts
                        m.isStreaming = true
                    }
                case .approvalRequest(let request):
                    // Interactive Allow/Deny card: the driver is blocked in
                    // awaitAnswer until the user resolves it.
                    let toolParts = toolPartsBox.parts
                    self.messageStore.update(id: assistantID) { m in
                        if !toolParts.isEmpty { m.parts = toolParts }
                        m.pendingApprovalID = request.id
                        m.pendingApprovalTool = request.tool
                        m.pendingApprovalMessage = request.message
                        m.isStreaming = true
                    }
                default:
                    switch WebChatTurnMutation.mutation(for: presentation) {
                    case .replaceText(let t, let finished, let streaming):
                        // Final answer: keep the accumulated thinking/answers
                        // and APPEND the final block (user directive
                        // 2026-09-11: nothing produced may be erased).
                        let merged = textAccumulator.absorbFinal(t)
                        self.messageStore.update(id: assistantID) { m in
                            m.content = merged; m.isFinished = finished; m.isStreaming = streaming
                            // Keep the tool spoilers: parts survive the
                            // final answer instead of being wiped.
                            if !toolPartsBox.parts.isEmpty { m.parts = toolPartsBox.parts }
                        }
                        self.finishWebTurn()
                    case .appendStatus(let line):
                        self.messageStore.update(id: assistantID) { m in
                            m.content = m.content.isEmpty ? line : "\(m.content)\n\(line)"
                            m.isStreaming = false
                            if !toolPartsBox.parts.isEmpty { m.parts = toolPartsBox.parts }
                        }
                        if WebChatEventPresenter.blocksUntilUserAction(event) || line.contains("fresh session") {
                            self.appState.resetWebSession(bindingKey)
                        }
                    case .none:
                        break
                    }
                }
            }
        }
        print("🔄 [ChatPanelView] Calling driver.runTurn with skipSend=\(skipDriverSend)")
        await driver.runTurn(userMessage: text, isFirstMessage: isFirst, emit: presentEvent,
                             skipSend: skipDriverSend,
                             preSendFingerprint: skipDriverSend ? preSendFingerprint : nil)
        print("🔄 [ChatPanelView] driver.runTurn completed")
        guard !WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: Task.isCancelled) else {
            finishWebTurn()
            return
        }

        // Injection failures happen before typing. Refresh the same live page
        // once, reload the persisted model/profile snapshot, and retry exactly
        // once; never create a second assistant bubble or a second remote chat.
        var finalConfig = effectiveConfig
        // Audit 2026-09-08 (Kimi SPA): when binding was postponed, capture the
        // remote chat id AFTER the send — the page URL/DOM gains it once the
        // first message lands. Later turns then navigate to this conversation.
        // The SPA updates its URL asynchronously after submit; binding
        // immediately can capture a STALE id (live: sidebar top link of the
        // previous chat). Wait for the URL to carry a chat id first.
        var boundMapping = remoteMapping
        if boundMapping == nil {
            for _ in 0..<20 {
                let currentURL = (try? await bridge.currentURL()) ?? ""
                if SendSubmissionPolicy.urlHasChatID(currentURL) { break }
                await bridge.wait(ms: 500)
            }
            // Bind ONLY when the URL itself carries the id (see second
            // binding attempt below for why sidebar candidates are stale).
            // The id comes from the same approved URL string (no live re-read).
            if let remote = await currentRemoteChat(bridge: bridge,
                                                 config: effectiveConfig),
               SendSubmissionPolicy.urlHasChatID(remote.url) {
                let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                    baseURL: remote.url,
                    vendor: effectiveConfig.vendor,
                    chatID: remote.id
                ) ?? remote.url
                boundMapping = WebRemoteChatMapping(key: bindingKey,
                                                    remoteChatID: remote.id,
                                                    remoteURL: canonical,
                                                    verifiedTitle: appState.selectedSession?.title)
                appState.saveWebRemoteChatMapping(boundMapping!)
            }
        }
        if let approvalMessage = approvalSignal.take() {
            appState.recordWebBrowserAction(action: "send_blocked_approval",
                                            config: effectiveConfig,
                                            projectID: projectID,
                                            chatID: chatID,
                                            modelID: effectiveConfig.selectedModel,
                                            effort: appState.selectedWebEffort,
                                            remoteChatID: boundMapping?.remoteChatID,
                                            detail: approvalMessage)
            messageStore.update(id: assistantID) { message in
                message.isFinished = true
                message.isStreaming = false
            }
            finishWebTurn()
            return
        }
        if retrySignal.take() != nil {
            appendWebStatus(to: assistantID, line: "Refreshing model catalog before retry…")
            self.appState.resetWebSession(bindingKey)
            _ = await appState.refreshWebModelsAndEffort(for: effectiveConfig,
                                                         projectID: projectID,
                                                         chatID: chatID)
            let refreshedConfig = WebProviderStore.load().first(where: { $0.id == effectiveConfig.id }) ?? effectiveConfig
            finalConfig = refreshedConfig
            if !refreshedConfig.discoveredModels.isEmpty {
                let retryDriver = WebChatDriver(bridge: bridge, executor: executor, selectors: selectors,
                                                config: refreshedConfig, projectRoot: workspacePath,
                                                accessLevel: appState.accessLevel, preparedSystemPrompt: webTurnSystemPrompt)
                await retryDriver.runTurn(
                    userMessage: text,
                    isFirstMessage: WebRetryContextLogic.isFirstMessageForRetry(originalIsFirst: isFirst),
                    emit: presentEvent
                )
                guard !WebChatCancellationLogic.shouldStopAfterDriver(isCancelled: Task.isCancelled) else {
                    finishWebTurn()
                    return
                }
            } else {
                appendWebStatus(to: assistantID, line: "Model catalog refresh returned no selectable models; retry stopped.")
            }
        }
        guard completionSignal.take() else {
            appendWebStatus(to: assistantID, line: "Web chat did not produce a verified final answer; the send was not marked complete. Check the browser session and retry.")
            finishWebTurn()
            return
        }
        // Audit 2026-09-08: bind ONLY when the URL itself carries the id —
        // sidebar DOM candidates can be a stale previous chat (live: Kimi
        // bound 1a07fa07 while the real chat was 1a0808b4). The id comes from
        // the same approved URL string (no live re-read across commits).
        if boundMapping == nil,
           let remote = await currentRemoteChat(bridge: bridge,
                                                 config: effectiveConfig),
           SendSubmissionPolicy.urlHasChatID(remote.url) {
            let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: remote.url,
                vendor: effectiveConfig.vendor,
                chatID: remote.id
            ) ?? remote.url
            boundMapping = WebRemoteChatMapping(key: bindingKey,
                                                remoteChatID: remote.id,
                                                remoteURL: canonical,
                                                verifiedTitle: appState.selectedSession?.title)
            appState.saveWebRemoteChatMapping(boundMapping!)
        }
        appState.recordWebBrowserAction(action: "send_completed",
                                        config: finalConfig,
                                        projectID: projectID,
                                        chatID: chatID,
                                        modelID: finalConfig.selectedModel,
                                        effort: appState.selectedWebEffort,
                                        remoteChatID: boundMapping?.remoteChatID,
                                        detail: "WebChatDriver completed")
        messageStore.update(id: assistantID) { message in
            let effortLabel = appState.selectedWebEffort?.displayName ?? "not supported"
            let remoteID = boundMapping?.remoteChatID ?? "pending"
            // User directive 2026-09-08: route metadata must NEVER be part of
            // the answer text. It ships as a routeInfo part rendered as chips
            // in the message header (provider · model · effort · remote chat).
            let chips: [String] = [
                finalConfig.displayName,
                finalConfig.selectedModel.isEmpty ? "auto" : finalConfig.selectedModel,
                "effort \(effortLabel)",
                "chat \(remoteID)"
            ]
            var routeParts = message.parts
            routeParts.removeAll { if case .routeInfo = $0 { return true } else { return false } }
            routeParts.append(.routeInfo(chips: chips))
            message.parts = routeParts
        }
        // Проверенный финальный ответ веб-чат провайдера — звук завершения,
        // если нет работающей цели (запрос 2026-11-13).
        playCompletionSoundIfIdle()
        finishWebTurn()
    }

}
