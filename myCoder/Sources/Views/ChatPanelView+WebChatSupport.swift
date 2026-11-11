import SwiftUI
import AppKit

extension ChatPanelView {
    /// Try SmartSend fallback before standard web chat driver.
    ///
    /// Attempts to send via:
    /// 1. Direct API (if network requests captured)
    /// 2. Smart element detection (if elements found)
    /// 3. Falls back to standard browser automation
    ///
    /// - Parameters:
    ///   - config: Web provider configuration
    ///   - bridge: Browser automation bridge
    ///   - message: Message to send
    /// - Returns: SmartSend result
    func trySmartSendFallback(
        config: WebProviderConfig,
        bridge: BrowserAutomationBridge,
        message: String
    ) async -> SmartSendResult {
        await SmartSend.execute(
            message: message,
            config: config,
            bridge: bridge,
            appState: appState
        )
    }

    @MainActor
    /// Binding contract:
    /// - Existing mapping → navigate to that remote chat (must verify) —
    ///   later turns continue exactly that conversation.
    /// - Fresh chat with a visible remote id → reuse it.
    /// - Fresh chat with NO id (audit 2026-09-08, Kimi SPA): return nil and
    ///   let the caller send first, then bind the id the page gains after the
    ///   send. Blocking the FIRST send because a URL has no id yet made Kimi
    ///   unusable; context mixing is impossible on a brand-new conversation.
    /// - freshSubmitPending (SmartSend already submitted): NEVER click "New
    ///   Chat" — the SPA URL may lag behind the submit and wiping the fresh
    ///   conversation (live: ChatGPT submit verified, then startNewSession
    ///   navigated home and discarded it).
    /// Current remote conversation from the live page URL — the single
    /// authoritative source for binding (audit 2026-09-08). Sidebar DOM
    /// candidates are NEVER used here: without a matching URL they are links
    /// to some other conversation (live: ChatGPT bound "WEB:f8f76…" and Kimi
    /// bound a previous chat while the real chat was created after the send).
    /// The id is derived from the SAME url string (no live re-read race).
    func currentRemoteChat(bridge: BrowserAutomationBridge,
                                   config: WebProviderConfig) async -> (id: String, url: String)? {
        guard let currentURL = try? await bridge.currentURL(),
              let host = URL(string: currentURL)?.host,
              host == URL(string: config.chatURL)?.host,
              let id = WebRemoteChatIdentityLogic.chatIDFromURL(currentURL),
              !id.isEmpty else { return nil }
        return (id, currentURL)
    }

    func bindWebRemoteChat(driver: WebChatDriver,
                                   bridge: BrowserAutomationBridge,
                                   config: WebProviderConfig,
                                   projectID: String,
                                   chatID: String,
                                   freshSubmitPending: Bool = false,
                                   isFirstTurn: Bool = false) async throws -> WebRemoteChatMapping? {
        let key = appState.webRemoteChatKey(for: config, projectID: projectID, chatID: chatID)
        let providerHost = URL(string: config.chatURL)?.host
        if var existing = appState.webRemoteChatMapping(for: config, projectID: projectID, chatID: chatID) {
            guard URL(string: existing.remoteURL)?.host == providerHost else {
                throw WebChatError.remoteChatBindingFailed("Stored remote chat belongs to another provider host; sending was blocked.")
            }
            let currentID = try? await driver.getCurrentChatID()
            if currentID != existing.remoteChatID {
                try await bridge.navigate(to: existing.remoteURL)
                try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
            }
            guard try await driver.getCurrentChatID() == existing.remoteChatID else {
                throw WebChatError.remoteChatBindingFailed("The browser did not verify the stored remote chat UUID after navigation; sending was blocked.")
            }
            existing.lastUsedAt = Date()
            existing.status = "verified"
            appState.saveWebRemoteChatMapping(existing)
            return existing
        }

        // Round 30: reuse an already-open remote conversation BEFORE creating a
        // new one. SmartSend may have just submitted into a fresh chat whose
        // URL now carries /chat/{id} or /c/{id}; letting startNewSession() run
        // first would click "New Chat" and wipe that submitted conversation.
        // EXCEPTION: a FIRST turn of a new local chat must NOT land in the
        // currently-open remote conversation — the tool preamble would arrive
        // on top of an unrelated history and the model keeps its earlier
        // refusals. Start a genuinely fresh remote chat instead.
        if !isFirstTurn,
           let remote = await currentRemoteChat(bridge: bridge,
                                                config: config),
           SendSubmissionPolicy.urlHasChatID(remote.url) {
            let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: remote.url,
                vendor: config.vendor,
                chatID: remote.id
            ) ?? remote.url
            let reused = WebRemoteChatMapping(key: key,
                                              remoteChatID: remote.id,
                                              remoteURL: canonical,
                                              verifiedTitle: appState.selectedSession?.title)
            appState.saveWebRemoteChatMapping(reused)
            try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
            return reused
        }
        guard !freshSubmitPending,
              let newURL = try await driver.startNewSession(),
              SendSubmissionPolicy.urlHasChatID(newURL),
              let remoteID = WebRemoteChatIdentityLogic.chatIDFromURL(newURL),
              let remoteURL = WebRemoteChatIdentityLogic.canonicalURL(
                baseURL: newURL,
                vendor: config.vendor,
                chatID: remoteID
              ),
              let remoteHost = URL(string: remoteURL)?.host,
              remoteHost == providerHost else {
            // Fallback: the browser may already be on a valid chat page.
            // Use the current page state instead of blocking the send.
            if let remote = await currentRemoteChat(bridge: bridge,
                                                     config: config),
               SendSubmissionPolicy.urlHasChatID(remote.url) {
                let canonical = WebRemoteChatIdentityLogic.canonicalURL(
                    baseURL: remote.url,
                    vendor: config.vendor,
                    chatID: remote.id
                ) ?? remote.url
                let mapping = WebRemoteChatMapping(key: key,
                                                    remoteChatID: remote.id,
                                                    remoteURL: canonical,
                                                    verifiedTitle: appState.selectedSession?.title)
                appState.saveWebRemoteChatMapping(mapping)
                try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
                return mapping
            }
            // Audit 2026-09-08: no mapping, no id, no new-chat URL change
            // (Kimi SPA keeps the shell URL until the first message lands).
            // Postpone binding: send first, capture the id afterwards.
            return nil
        }
        let mapping = WebRemoteChatMapping(key: key,
                                            remoteChatID: remoteID,
                                            remoteURL: remoteURL,
                                            verifiedTitle: appState.selectedSession?.title)
        appState.saveWebRemoteChatMapping(mapping)
        try? await bridge.waitForSelector(selector: driver.selectors.input, timeout: 10_000)
        return mapping
    }

    /// Returns a refresh reason only for failures that can be fixed by a live
    /// model/effort catalog probe. Typed injection events are authoritative;
    /// generic errors use conservative keyword matching as a compatibility
    /// fallback for older driver implementations.
    func webCatalogRefreshReason(for event: WebChatEvent) -> String? {
        switch event {
        case .modelInjectionFailed(let message), .effortInjectionFailed(let message):
            return message
        case .error(let message):
            let normalized = message.lowercased()
            let keywords = ["model", "effort", "injection", "not found in web ui", "not found in the web provider"]
            guard keywords.contains(where: { normalized.contains($0) }) else { return nil }
            return message
        default:
            return nil
        }
    }

    /// Refreshes the live model catalog once per provider/project/chat turn.
    /// Generic string errors use this bounded background refresh as a diagnostic
    /// fallback. Typed pre-send injection failures use the automatic one-shot
    /// retry path above, so no duplicate prompt is created.
    @MainActor
    func scheduleWebCatalogRefreshIfNeeded(reason: String,
                                                    key: String,
                                                    config: WebProviderConfig,
                                                    projectID: String,
                                                    chatID: String,
                                                    assistantID: String) {
        guard !webCatalogRefreshKeys.contains(key) else { return }
        webCatalogRefreshKeys.insert(key)
        appendWebStatus(to: assistantID, line: "Model/effort injection failed: \(reason)\nRefreshing the live model catalog before your next retry…")
        Task { @MainActor in
            let result = await appState.refreshWebModelsAndEffort(for: config,
                                                                  projectID: projectID,
                                                                  chatID: chatID)
            let summary = [result.modelsMsg, result.effortMsg]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            appendWebStatus(to: assistantID,
                            line: summary.isEmpty ? "Model catalog refresh finished. Retry the message." : "Model catalog refresh finished: \(summary). Retry the message.")
        }
    }

    /// Appends a status line to the assistant bubble without ending the turn.
    @MainActor
    func appendWebStatus(to assistantID: String, line: String) {
        messageStore.update(id: assistantID) { m in
            m.content = m.content.isEmpty ? line : "\(m.content)\n\(line)"
            m.isStreaming = false
        }
    }

    func roleString(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    @MainActor
    func finishWebTurn() {
        serveTimeoutTask?.cancel()
        serveTimeoutTask = nil
        appState.isLoading = false
        appState.isStreaming = false
        streamingText = ""
        currentAssistantMessageID = nil
        activeWebProviderID = nil
        activeWebChatID = nil
        captchaSolverContext = nil
    }
}
