import Foundation
import SwiftUI
import AppKit

/// Выбор модели и провайдера.
extension AppState {
    var availableModels: [String] {
        ProviderSettingsLogic.mergeModelIDs(
            serverProviders: serverProviders,
            customProviders: customProviders,
            isDisabled: { [defaults] providerID, modelID in
                DisabledModelStore.isDisabled(
                    providerID: providerID,
                    modelID: modelID,
                    defaults: defaults
                )
            }
        )
    }

    /// Effective selected model — for web providers resolve from their config
    /// since AppState.selectedModel is empty for web providers.
    func effectiveSelectedModel() -> String {
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let cfg = WebProviderStore.load().first(where: { $0.id == webID }) {
            return WebProviderSelectionLogic.effectiveSelectedModel(for: cfg)
        }
        return selectedModel
    }

    var modelsForSelectedProvider: [String] {
        // Web provider selected → its real (discovered) models (plan Раздел 13 п.4).
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let cfg = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            return WebProviderConnectivity.models(for: cfg)
        }
        // Local provider selected → its loaded models.
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == selectedProviderID }) {
            let disabled = DisabledModelStore.disabledModels(for: local.id, defaults: defaults)
            return local.models.filter { !disabled.contains($0) }
        }
        let disabled = DisabledModelStore.disabledModels(for: selectedProviderID, defaults: defaults)
        return ProviderSettingsLogic.models(
            for: selectedProviderID,
            in: serverProviders,
            customProviders: customProviders
        ).filter { !disabled.contains($0) }
    }

    var supportsToolcallForSelection: Bool {
        ProviderCapabilityGates.canUseTools(
            modelID: effectiveSelectedModel(),
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            providers: serverProviders,
            customProviders: customProviders
        )
    }

    /// The provider the user explicitly picked; survives fallbacks while the
    /// provider is offline and is restored once it reappears.
    var preferredProviderID: String {
        defaults.string(forKey: "com.mycoder.preferredProviderID")
            ?? defaults.string(forKey: "com.mycoder.selectedProviderID")
            ?? ""
    }

    var preferredModelID: String {
        defaults.string(forKey: "com.mycoder.preferredModelID")
            ?? defaults.string(forKey: "com.mycoder.selectedModel")
            ?? ""
    }

    func selectModel(_ modelID: String, persistPreference: Bool = true) {
        defer { persistSelectionToSelectedSession() }
        if modelID.isEmpty {
            selectedModel = ""
            defaults.set("", forKey: "com.mycoder.selectedModel")
            if persistPreference {
                defaults.set("", forKey: "com.mycoder.preferredModelID")
            }
            return
        }
        guard modelsForSelectedProvider.contains(modelID) else { return }
        selectedModel = modelID
        defaults.set(modelID, forKey: "com.mycoder.selectedModel")
        if persistPreference {
            defaults.set(modelID, forKey: "com.mycoder.preferredModelID")
        }
        // Audit 2026-09-06: for a WEB provider the model lives in the web
        // config, not in `selectedModel`. Without this, the API/UI selection
        // never reached WebChatDriver and sends fell back to a stale model.
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) {
            var configs = WebProviderStore.load()
            if let idx = configs.firstIndex(where: { $0.id == webID }) {
                let updated = WebProviderSelectionLogic.selectingModel(modelID, in: configs[idx])
                if updated != configs[idx] {
                    configs[idx] = updated
                    WebProviderStore.save(configs)
                }
            }
        }
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) {
            updateWebProvider(webID, modelID: modelID)
            if let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
                Task { @MainActor in
                    self.recordWebBrowserAction(action: "model_selected",
                                                config: config,
                                                modelID: modelID,
                                                effort: self.selectedWebEffort,
                                                detail: "Composer model selection")
                }
            }
            selectedVariant = ""
            return
        }
        selectedVariant = ProviderSettingsLogic.normalizedVariant(
            selectedVariant.isEmpty ? nil : selectedVariant,
            for: modelID,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        ) ?? ""
    }

    /// Store the current provider/model on the open chat so reopening it
    /// restores the same selection.
    func persistSelectionToSelectedSession() {
        guard let sessionID = selectedSession?.id else { return }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].modelID = selectedModel
            sessions[index].providerID = selectedProviderID
        }
        DatabaseBridge.shared.setSessionModel(
            sessionId: sessionID,
            modelID: selectedModel,
            providerID: selectedProviderID
        )
    }

    /// Restore the provider/model a chat used last. Chats without their own
    /// selection fall back to the last selection made outside any chat.
    func restoreSelection(for session: ChatSession) {
        let selection = SessionModelSelectionLogic.resolve(
            sessionProviderID: session.providerID,
            sessionModelID: session.modelID,
            preferredProviderID: defaults.string(forKey: "com.mycoder.preferredProviderID"),
            preferredModelID: defaults.string(forKey: "com.mycoder.preferredModelID")
        )
        guard !selection.providerID.isEmpty else { return }
        if selection.providerID != selectedProviderID {
            selectProvider(selection.providerID, persistPreference: false)
        }
        guard let modelID = SessionModelSelectionLogic.applyableModel(
            selection.modelID,
            availableModels: modelsForSelectedProvider
        ) else { return }
        if modelID != selectedModel {
            selectModel(modelID, persistPreference: false)
        }
    }

    func validateAndReconcileSelections() {
        let rawOptions = rawProviderOptions(includeDisabled: false)
        let canonicalID = ProviderDuplicationLogic.canonicalID(
            for: selectedProviderID,
            in: rawOptions
        )
        if canonicalID != selectedProviderID {
            selectProvider(canonicalID, persistPreference: false)
        }

        let options = ProviderDuplicationLogic.deduplicatedOptions(rawOptions)
        if options.isEmpty {
            // Only an enabled server row may be picked as a fallback — a row
            // the user switched off must never become the active provider.
            if selectedProviderID.isEmpty,
               let firstServer = serverProviders.first(where: {
                   !ProviderEnablementStore.isDisabled($0.id, defaults: defaults)
               }) {
                selectProvider(firstServer.id, persistPreference: false)
            }
            return
        }

        // Restore the user's explicit choice as soon as it is available again.
        if let restored = SelectionRestoreLogic.resolvedProviderID(
            preferred: preferredProviderID,
            current: selectedProviderID,
            options: options.map(\.id)
        ) {
            selectProvider(restored, persistPreference: false)
            restorePreferredModelIfAvailable()
            return
        }

        if selectedProviderID.isEmpty || !options.contains(where: { $0.id == selectedProviderID }) {
            // Temporary fallback — must not overwrite the stored preference.
            selectProvider(options[0].id, persistPreference: false)
            return
        }

        restorePreferredModelIfAvailable()

        let result = ProviderSelectionLogic.cascade(
            to: selectedProviderID,
            currentModelID: selectedModel,
            currentVariant: selectedVariant.isEmpty ? nil : selectedVariant,
            serverProviders: serverProviders,
            customProviders: customProviders
        )
        selectedModel = result.modelID
        defaults.set(result.modelID, forKey: "com.mycoder.selectedModel")
        selectedVariant = result.variant ?? ""
    }

    private func restorePreferredModelIfAvailable() {
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            let resolved = WebSelectionReconciliationLogic.modelForRestore(
                config: config,
                globalPreferredModel: preferredModelID,
                availableModels: WebProviderConnectivity.models(for: config)
            )
            var providers = WebProviderStore.load(defaults: defaults)
            if let index = providers.firstIndex(where: { $0.id == webID }),
               providers[index].selectedModel != resolved {
                providers[index].selectedModel = resolved
                WebProviderStore.save(providers, defaults: defaults)
            }
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            return
        }
        if let restoredModel = SelectionRestoreLogic.resolvedModelID(
            preferred: preferredModelID,
            current: selectedModel,
            options: modelsForSelectedProvider
        ) {
            selectModel(restoredModel, persistPreference: false)
        }
    }

    var availableVariantsForSelectedModel: [String] {
        ProviderSettingsLogic.availableVariants(
            for: selectedModel,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        )
    }

    var supportsReasoningForSelectedModel: Bool {
        ProviderSettingsLogic.supportsReasoning(
            for: selectedModel,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        )
    }

    /// Whether the currently selected provider is an ACP-enabled custom provider.
    var isSelectedACPProvider: Bool {
        guard let custom = customProviders.first(where: { $0.id == selectedProviderID }) else {
            return false
        }
        return custom.type == .acp && custom.acpEnabled
    }

    /// Whether the currently selected provider is a browser web provider.
    /// Used to hide non-web controls (variant/effort menus) from the
    /// composer — web effort is discovered with each model and injected
    /// by the driver, never hand-picked (user directive 2026-09-06).
    var isSelectedWebProvider: Bool {
        WebProviderConnectivity.configID(fromOptionID: selectedProviderID) != nil
    }

    /// Returns an `ACPClient` for the currently selected ACP provider, or nil.
    var acpClient: ACPClient? {
        guard isSelectedACPProvider,
              let custom = customProviders.first(where: { $0.id == selectedProviderID }),
              let url = URL(string: custom.baseURL) else {
            return nil
        }
        let key = custom.apiKey
        return ACPClient(baseURL: url, apiKey: key)
    }

    func applySendSelections(_ selections: SessionSendSelections) {
        if let agentMode = selections.agentMode {
            self.agentMode = agentMode
        }
        if let providerID = selections.providerID, !providerID.isEmpty {
            if providerOptions.contains(where: { $0.id == providerID }) {
                selectProvider(providerID)
            }
        }
        if let modelID = selections.modelID, !modelID.isEmpty {
            if modelsForSelectedProvider.contains(modelID) {
                selectModel(modelID)
            } else if providerOptions.contains(where: { $0.id == selections.providerID ?? selectedProviderID }) {
                selectModel(modelID)
            }
        }
        if let variant = selections.variant, !variant.isEmpty {
            selectedVariant = ProviderSettingsLogic.normalizedVariant(
                variant,
                for: selectedModel,
                in: serverProviders,
                providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
                customProviders: customProviders
            ) ?? variant
        }
        if agentMode == .plan,
           !ProviderCapabilityGates.canSelectPlanAgent(
               modelID: selectedModel,
               providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
               providers: serverProviders,
               customProviders: customProviders
           ) {
            agentMode = .build
        }
    }

    func applyAccessLevelToServer() async {
        guard serverConnected else { return }
        let patch: [String: Any] = [
            "permission": AccessLevelPermissionLogic.permissionPatch(for: accessLevel)
        ]
        do {
            _ = try await mimoClient.updateGlobalConfig(patch)
        } catch {
            print("Failed to update permission config: \(error)")
        }
    }

    func syncAccessLevelFromServer() async {
        do {
            let config = try await mimoClient.globalConfig()
            let mapped = AccessLevelPermissionLogic.accessLevel(from: config.permission?.asDictionary)
            await MainActor.run {
                isSyncingAccessLevel = true
                self.accessLevel = mapped
                isSyncingAccessLevel = false
            }
        } catch {
            print("Failed to sync access level: \(error)")
        }
    }
}
