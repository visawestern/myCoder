import Foundation

/// Панель веб-провайдера и связи удалённых чатов.
///
/// Здесь нет WebKit: страницу показывает AntiBrowser через каст
/// (`CastPanelHost` / `BrowserCastView`), а этот файл только хранит, какая
/// вкладка провайдера должна быть видна в текущем чате.
extension AppState {
    /// Ensure the provider's page is surfaced in the visible browser panel.
    /// Call when a WEB provider turn starts.
    @MainActor
    func showWebBrowserPanel(for config: WebProviderConfig,
                             projectID: String,
                             chatID: String) {
        webBrowserPanelConfig = WebBrowserPanelConfig(
            providerID: config.id,
            providerName: config.displayName,
            projectID: projectID,
            chatID: chatID
        )
        webBrowserLastProviderID = config.id
    }

    /// Hide the visible panel. The AntiBrowser tab keeps its state (login,
    /// conversation, stream) for the next web turn because the profile is
    /// persistent and the tab is not closed.
    @MainActor
    func hideWebBrowserPanel() {
        webBrowserPanelConfig = nil
    }

    /// Next action of the top-bar Browser button, or nil when there is no web
    /// provider to open (the button is hidden in that case).
    ///
    /// Input: visible panel, composer provider, last shown web provider and
    /// the configured web providers. Output: `.hide`, `.show(config)` or nil.
    /// Dependencies: `WebBrowserToggleLogic` (pure rules).
    @MainActor
    var webBrowserToggleAction: WebBrowserToggleAction? {
        WebBrowserToggleLogic.action(
            panelConfig: webBrowserPanelConfig,
            selectedProviderOptionID: selectedProviderID,
            activeProviderID: webBrowserLastProviderID,
            configs: WebProviderStore.load(defaults: defaults),
            projectID: selectedWorkspace?.id ?? selectedWorkspace?.path ?? "global",
            chatID: selectedSession?.id ?? "provider-default"
        )
    }

    /// Hide a visible browser panel or re-open it for the current chat.
    /// The AntiBrowser tab itself is never closed: hiding only stops showing
    /// the cast, so login and an in-flight stream survive.
    @MainActor
    func toggleWebBrowserPanel() {
        guard let action = webBrowserToggleAction else { return }
        switch action {
        case .show(let config):
            webBrowserPanelConfig = config
        case .hide:
            hideWebBrowserPanel()
        }
    }

    /// User directive 2026-09-09: switching to another chat/project surfaces
    /// THAT chat's browser tab when the panel is already open; otherwise
    /// nothing changes.
    @MainActor
    func showPanelForChatIfPooled(projectID: String, chatID: String) {
        guard let existing = webBrowserPanelConfig else { return }
        guard let provider = WebProviderStore.load(defaults: defaults)
            .first(where: { $0.id == existing.providerID }) else { return }
        webBrowserPanelConfig = WebBrowserPanelConfig(
            providerID: provider.id,
            providerName: provider.displayName,
            projectID: projectID,
            chatID: chatID
        )
    }

    /// Идентификатор удалённого чата. Отдельного номера входа больше нет:
    /// вход один на профиль AntiBrowser, поэтому в ключе стоит `default`.
    @MainActor
    func webRemoteChatKey(for config: WebProviderConfig,
                          projectID: String,
                          chatID: String) -> WebRemoteChatKey {
        WebRemoteChatKey(providerID: config.id,
                         activeSessionID: "default",
                         projectID: projectID,
                         localChatID: chatID)
    }

    @MainActor
    func webRemoteChatMapping(for config: WebProviderConfig,
                              projectID: String,
                              chatID: String) -> WebRemoteChatMapping? {
        WebRemoteChatStore.mapping(for: webRemoteChatKey(for: config, projectID: projectID, chatID: chatID),
                                   defaults: defaults)
    }

    @MainActor
    func saveWebRemoteChatMapping(_ mapping: WebRemoteChatMapping) {
        WebRemoteChatStore.upsert(mapping, defaults: defaults)
    }

    @MainActor
    func clearWebRemoteChats(providerID: String, activeSessionID: String? = nil) {
        WebRemoteChatStore.clear(providerID: providerID, activeSessionID: activeSessionID, defaults: defaults)
    }

    /// Stop the active browser generation for a provider. This is separate from
    /// cancelling the Swift task: the vendor page must receive its own stop
    /// action or it can keep consuming tokens in the background.
    @MainActor
    func stopWebGeneration(providerID: String,
                           projectID: String,
                           chatID: String) async {
        guard (try? EngineStatusCenter.shared.requireEngine()) != nil else { return }
        let tabKey = AntiBrowserTabManager.makeKey(providerID: providerID,
                                                   projectID: projectID,
                                                   chatID: chatID)
        let bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        try? await bridge.stopGeneration()
    }

    /// Refresh the *real* model list for a web provider. The login lives in the
    /// persistent AntiBrowser profile, so this method navigates the provider's
    /// tab, waits for the composer, and reads the model dropdown. It returns an
    /// actionable message instead of silently leaving 0 models.
    @MainActor
    func refreshWebModels(for config: WebProviderConfig,
                          projectID: String? = nil,
                          chatID: String? = nil) async -> String {
        // Prefer the user-picked selector but always retain catalog fallbacks.
        // A stale custom selector must not hide the live model menu.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        let selector = [
            config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            catalogEntry?.modelDropdown ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        if selector.isEmpty {
            return L.t(AppLocalizationKey.locWebNoSelectorYet)
        }

        let selectors = WebVendorSelectors(
            input: "textarea, div[contenteditable='true']",
            sendButton: "button[type='submit'], button[aria-label*='send'], button[data-testid='send-button']",
            responseContainer: "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: "button[aria-label*='stop'], button[data-testid='stop-button'], button[class*='stop']"
        )
        let bridge: BrowserAutomationBridge
        do {
            try EngineStatusCenter.shared.requireEngine()
            let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                       projectID: projectID ?? "global",
                                                       chatID: chatID ?? "provider-default")
            bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        } catch {
            return error.localizedDescription
        }
        do {
            try await bridge.navigate(to: config.chatURL)
            var inputFound = false
            for _ in 0..<30 {
                if try await bridge.exists(selector: selectors.input) {
                    inputFound = true
                    break
                }
                await bridge.wait(ms: 500)
            }
            guard inputFound else {
                return L.t(AppLocalizationKey.locWebInputNotFound)
            }
            // Login-wall gate: a logged-out vendor page can never yield
            // models — the old flow scraped login CTAs and sidebar chrome as
            // "models" (live ChatGPT evidence 2026-09-06). Report honestly.
            if await WebModelDiscovery.isLoginWall(using: bridge) {
                return "The \(config.displayName) page shows a login screen — open the provider login, sign in, then refresh models again."
            }
            let models = await WebModelDiscovery.discoverAllModels(using: bridge,
                                                                    dropdownSelector: selector,
                                                                    vendor: config.vendor)
            guard let found = models else {
                return String(format: L.t(AppLocalizationKey.locWebModelListFailed), config.displayName)
            }
            let capabilityModels = await WebModelDiscovery.discoverModelCapabilities(
                using: bridge,
                dropdownSelector: selector,
                vendor: config.vendor,
                models: found,
                effortDropdownSelector: config.effortDropdown ?? catalogEntry?.effortDropdown
            )
            let resolvedModels = capabilityModels.isEmpty ? found : capabilityModels
            let discoveredEfforts = Array(Set(resolvedModels.flatMap(\.availableEfforts))).sorted { $0.rawValue < $1.rawValue }
            if !config.selectedModel.isEmpty {
                let itemSelector = catalogEntry?.modelItem ?? "[role='option'], [class*='model'], li"
                var restored = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: config.selectedModel)) == true
                if !restored {
                    for selector in ["[role='option']", "[role='menuitem']", "[class*='model-item']"] {
                        if (try? await bridge.clickVisibleTextExact(selector: selector, text: config.selectedModel)) == true {
                            restored = true
                            break
                        }
                    }
                }
                if restored { await bridge.wait(ms: 250) }
            }
            var updated = WebModelRefreshLogic.replacing(config: config, with: resolvedModels)
            updated.discoveredEffortLevels = discoveredEfforts
            WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
            if resolvedModels.isEmpty {
                return String(format: L.t(AppLocalizationKey.locWebModelListFailed), config.displayName)
            }
            if selectedProviderID == "web:\(config.id)" {
                selectProvider(selectedProviderID, persistPreference: false)
            }
            let count = resolvedModels.count
            let plural = count == 1 ? "" : "s"
            // Audit 2026-09-06: the message MUST match what the composer
            // actually offers. allModels filters tier-gated entries
            // (isSelectable=false); reporting the raw discovered count made
            // the user see "loaded 10" while the card showed 3.
            let refreshedConfig = WebModelRefreshLogic.replacing(config: config, with: resolvedModels)
            let selectableCount = refreshedConfig.allModels.count
            let gatedCount = resolvedModels.filter { !$0.isSelectable }.count
            let baseMessage = String(format: L.t(AppLocalizationKey.locWebLoadedModels), selectableCount, plural, config.displayName)
            let gatedNote = gatedCount > 0
                ? " \(gatedCount) more require a higher plan (not selectable)."
                : ""
            return baseMessage + gatedNote
        } catch {
            return String(format: L.t(AppLocalizationKey.locWebRefreshFailed), error.localizedDescription)
        }
    }
}
