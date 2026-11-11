import Foundation
import SwiftUI
import AppKit

/// Веб-провайдеры: усилие и сессии чата.
extension AppState {
    var selectedWebProviderConfig: WebProviderConfig? {
        guard let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) else { return nil }
        return WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID })
    }

    var availableWebEffortsForSelectedProvider: [WebEffort] {
        guard let config = selectedWebProviderConfig else { return [] }
        return WebProviderSelectionLogic.availableEfforts(
            for: config,
            modelID: effectiveSelectedModel()
        )
    }

    var selectedWebEffort: WebEffort? {
        guard let config = selectedWebProviderConfig else { return nil }
        return WebSelectionReconciliationLogic.effortForModel(
            config: config,
            modelID: effectiveSelectedModel(),
            availableEfforts: availableWebEffortsForSelectedProvider
        )
    }

    func updateWebProvider(_ configID: String,
                                   modelID: String? = nil,
                                   effort: WebEffort? = nil) {
        var providers = WebProviderStore.load(defaults: defaults)
        guard let index = providers.firstIndex(where: { $0.id == configID }) else { return }
        if let modelID {
            providers[index] = WebProviderSelectionLogic.selectingModel(
                modelID,
                in: providers[index],
                availableModels: WebProviderConnectivity.models(for: providers[index])
            )
        }
        if let effort {
            providers[index] = WebProviderSelectionLogic.selectingEffort(effort, in: providers[index])
        }
        WebProviderStore.save(providers, defaults: defaults)
    }

    func selectWebEffort(_ effort: WebEffort) {
        guard let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
              availableWebEffortsForSelectedProvider.contains(effort) else { return }
        updateWebProvider(webID, effort: effort)
        if let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            Task { @MainActor in
                self.recordWebBrowserAction(action: "effort_selected",
                                            config: config,
                                            modelID: config.selectedModel,
                                            effort: effort,
                                            detail: "Composer effort selection")
            }
        }
        objectWillChange.send()
    }

    /// Refresh available effort/thinking levels for a web provider by reading
    /// the effort dropdown on the provider's web page.
    /// Returns a status message describing the result.
    @MainActor
    func refreshWebEffort(for config: WebProviderConfig,
                          projectID: String? = nil,
                          chatID: String? = nil) async -> String {
        #if canImport(WebKit)
        guard let effortSelector = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)?.effortDropdown else {
            return L.t(AppLocalizationKey.locWebEffortNoSelector)
        }
        let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
        guard let store = WebSessionManager.restore(providerId: config.id,
                                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                    sessionID: sessionID),
              !store.cookies.isEmpty,
              !WebSessionManager.isExpired(store) else {
            return L.t(AppLocalizationKey.locWebEffortLoginFirst)
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
        var localStorageWarning: String?
        do {
            let payload = WebSessionRestorationLogic.payload(from: store)
            try await bridge.setCookies(payload.cookies)
            try await bridge.navigate(to: config.chatURL)
            do {
                try await bridge.setLocalStorage(payload.localStorage)
                if !payload.localStorage.isEmpty {
                    try await bridge.navigate(to: config.chatURL)
                }
            } catch {
                localStorageWarning = " (localStorage restore unavailable: \(error.localizedDescription))"
            }
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
            guard let efforts = await WebModelDiscovery.discoverEffort(using: bridge,
                                                                       effortDropdownSelector: effortSelector,
                                                                       vendor: config.vendor) else {
                return String(format: L.t(AppLocalizationKey.locWebEffortReadFailed), config.displayName)
            }
            var updated = config
            updated.effort = efforts.first ?? .medium
            updated.discoveredEffortLevels = efforts
            WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
            if selectedProviderID == "web:\(config.id)" {
                selectProvider(selectedProviderID, persistPreference: false)
            }
            let count = efforts.count
            let plural = count == 1 ? "" : "s"
            let message = String(format: L.t(AppLocalizationKey.locWebLoadedEffort), count, plural, config.displayName)
            return message + (localStorageWarning ?? "")
        } catch {
            return String(format: L.t(AppLocalizationKey.locWebEffortRefreshFailed), error.localizedDescription)
        }
        #else
        return L.t(AppLocalizationKey.locWebRequiresWebKit)
        #endif
    }

    /// Refresh the complete model capability snapshot. `refreshWebModels` already
    /// probes effort and parameter controls for every validated model; calling
    /// the older provider-global effort probe afterwards would overwrite the
    /// atomic per-model result with an ambiguous union.
    @MainActor
    func refreshWebModelsAndEffort(for config: WebProviderConfig,
                                   projectID: String? = nil,
                                   chatID: String? = nil) async -> (modelsMsg: String, effortMsg: String) {
        let modelsMsg = await refreshWebModels(for: config, projectID: projectID, chatID: chatID)
        let refreshedConfig = WebProviderStore.load().first(where: { $0.id == config.id }) ?? config
        let profiledCount = refreshedConfig.discoveredModels.filter { !$0.availableEfforts.isEmpty }.count
        let effortMsg = profiledCount == 0
            ? "No per-model effort controls were confirmed."
            : "Per-model effort detected for \(profiledCount) model(s)."
        return (modelsMsg, effortMsg)
    }

    func webSessionIsFirstTurn(_ providerID: String) -> Bool { !webSessionStarted.contains(providerID) }

    func markWebSessionStarted(_ providerID: String) { webSessionStarted.insert(providerID) }

    func resetWebSession(_ providerID: String) { webSessionStarted.remove(providerID) }

    func webSessionIsFirstTurn(_ key: WebRemoteChatKey) -> Bool { !webSessionStarted.contains(key.storageKey) }

    func markWebSessionStarted(_ key: WebRemoteChatKey) { webSessionStarted.insert(key.storageKey) }

    func resetWebSession(_ key: WebRemoteChatKey) { webSessionStarted.remove(key.storageKey) }
}
