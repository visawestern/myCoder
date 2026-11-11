import Foundation
import SwiftUI
import AppKit

/// Переключение провайдера и проверка связи.
extension AppState {
    func selectProvider(_ providerID: String, persistPreference: Bool = true) {
        defer { persistSelectionToSelectedSession() }
        selectedProviderID = providerID
        providerConnectivity[providerID] = false
        Task { await refreshProviderConnectivity(providerID) }
        defaults.set(providerID, forKey: "com.mycoder.selectedProviderID")
        if persistPreference {
            defaults.set(providerID, forKey: "com.mycoder.preferredProviderID")
        }

        // Web providers are persisted locally rather than returned by
        // `mimo serve`, so ProviderSelectionLogic cannot resolve their models.
        // Select their discovered model (or the clearly-labelled pre-discovery
        // fallback) directly instead of leaving the chat with an empty model.
        if let webID = WebProviderConnectivity.configID(fromOptionID: providerID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            let models = WebProviderConnectivity.models(for: config)
            let preferred = WebSelectionReconciliationLogic.modelForRestore(
                config: config,
                globalPreferredModel: selectedModel,
                availableModels: models
            )
            selectedModel = preferred
            defaults.set(preferred, forKey: "com.mycoder.selectedModel")
            selectedVariant = ""
            updateWebProvider(webID, modelID: preferred)
            return
        }

        // Local providers carry their own model lists (persisted at
        // detect/refresh time) — the server+custom cascade below knows
        // nothing about them and would blank the model. Resolve from the
        // local list instead, then refresh it in the background so a stale
        // single-model list (e.g. from before credentials existed) heals.
        let localConfig = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID })
        if let local = localConfig {
            let resolved = LocalModelRefreshLogic.reconcile(current: selectedModel, fresh: local.models)
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            Task { await self.refreshLocalModels(providerID) }
        } else {
            let result = ProviderSelectionLogic.cascade(
                to: providerID,
                currentModelID: selectedModel,
                currentVariant: selectedVariant.isEmpty ? nil : selectedVariant,
                serverProviders: serverProviders,
                customProviders: customProviders
            )
            selectedModel = result.modelID
            defaults.set(result.modelID, forKey: "com.mycoder.selectedModel")
            selectedVariant = result.variant ?? ""
        }

        // Local providers carry their own model lists (persisted at
        // detect/refresh time) — the server+custom cascade above knows
        // nothing about them and would blank the model. Resolve from the
        // local list instead, then refresh it in the background so a stale
        // single-model list (e.g. from before credentials existed) heals.
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID }) {
            let resolved = LocalModelRefreshLogic.reconcile(current: selectedModel, fresh: local.models)
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            Task { await self.refreshLocalModels(providerID) }
        }

        if agentMode == .plan,
           !ProviderCapabilityGates.canSelectPlanAgent(
               modelID: effectiveSelectedModel(),
               providerID: providerID,
               providers: serverProviders,
               customProviders: customProviders
           ) {
            agentMode = .build
            Task { @MainActor in
                self.notificationService.info(
                    title: L.t(AppLocalizationKey.locModeSwitched),
                    message: L.t(AppLocalizationKey.locPlanNotSupported)
                )
            }
        }
    }

    @MainActor
    private func refreshProviderConnectivity(_ providerID: String) async {
        guard !providerID.isEmpty else { return }
        // A row the user switched off is never probed — it stays "offline".
        if ProviderEnablementStore.isDisabled(providerID, defaults: defaults) {
            providerConnectivity[providerID] = false
            return
        }
        if serverConnected && serverProviders.contains(where: { $0.id == providerID }) {
            providerConnectivity[providerID] = true
            return
        }
        if let webID = WebProviderConnectivity.configID(fromOptionID: providerID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            providerConnectivity[providerID] = WebProviderConnectivity.isConnected(config)
            return
        }
        if let local = LocalProviderLogic.load().first(where: { $0.id == providerID && $0.isEnabled }) {
            providerConnectivity[providerID] = await probeProviderURL(local.healthURL, headers: local.authHeaders())
            return
        }
        if let custom = customProviders.first(where: { $0.id == providerID && $0.isEnabled }) {
            let base = custom.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            providerConnectivity[providerID] = await probeProviderURL("\(base)/models")
            return
        }
        providerConnectivity[providerID] = false
    }

    private func probeProviderURL(_ string: String, headers: [String: String] = [:]) async -> Bool {
        guard let url = URL(string: string) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return (200..<500).contains(status)
        } catch {
            return false
        }
    }
}
