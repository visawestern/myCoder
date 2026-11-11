import Foundation
import SwiftUI
import AppKit

/// Каталог провайдеров и правила включения.
extension AppState {
    var providerOptions: [ProviderOption] {
        buildProviderOptions(includeDisabled: false)
    }

    /// Provider list for Settings: disabled custom/local providers stay
    /// visible so they can be re-enabled. The send picker keeps using
    /// `providerOptions`, which only exposes enabled providers.
    var manageableProviderOptions: [ProviderOption] {
        buildProviderOptions(includeDisabled: true)
    }

    private func buildProviderOptions(includeDisabled: Bool) -> [ProviderOption] {
        ProviderDuplicationLogic.deduplicatedOptions(
            rawProviderOptions(includeDisabled: includeDisabled)
        )
    }

    func rawProviderOptions(includeDisabled: Bool) -> [ProviderOption] {
        var options = ProviderSettingsLogic.allProviderOptions(
            serverProviders: serverProviders,
            customProviders: customProviders,
            includeDisabled: includeDisabled
        ).map { option in
            guard let custom = customProviders.first(where: { $0.id == option.id }),
                  custom.type == .openCodeZen else {
                return option
            }
            return ProviderOption(
                id: option.id,
                name: option.name,
                isCustom: true,
                isConnected: custom.isEnabled && !custom.models.isEmpty
            )
        }
        // Server catalog rows have no native enable flag — the switch state
        // lives in ProviderEnablementStore (user directive: one switch
        // everywhere, no status dots).
        if !includeDisabled {
            options = options.filter { option in
                option.isCustom || !ProviderEnablementStore.isDisabled(option.id, defaults: defaults)
            }
        }
        // Local providers (Ollama/OpenCode/MiMo CLI) — plan Раздел 1.
        options += LocalProviderLogic.providerOptions(
            from: LocalProviderLogic.load(),
            includeDisabled: includeDisabled
        )
        // Connected web providers (only after cookies captured) — plan Раздел 13 п.4.
        options += WebProviderConnectivity.providerOptions(
            WebProviderStore.load(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ).filter { includeDisabled || !ProviderEnablementStore.isDisabled($0.id, defaults: defaults) }
        return options
    }

    /// Whether a provider row is switched on. Custom and local providers keep
    /// their own flag; server catalog and web rows use the shared store.
    func isProviderEnabled(_ providerID: String) -> Bool {
        if let custom = customProviders.first(where: { $0.id == providerID }) {
            return custom.isEnabled
        }
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID }) {
            return local.isEnabled
        }
        return !ProviderEnablementStore.isDisabled(providerID, defaults: defaults)
    }

    /// Switch a provider row on/off. The selected provider is dropped when it
    /// is switched off so the composer never keeps a dead provider.
    func setProviderEnabled(_ providerID: String, isEnabled: Bool) {
        if customProviders.contains(where: { $0.id == providerID }) {
            setCustomProviderEnabled(providerID, isEnabled: isEnabled)
            return
        }
        if LocalProviderLogic.load(defaults: defaults).contains(where: { $0.id == providerID }) {
            LocalProviderLogic.setEnabled(id: providerID, isEnabled: isEnabled, defaults: defaults)
        } else {
            ProviderEnablementStore.setDisabled(
                !isEnabled,
                providerID: providerID,
                defaults: defaults
            )
        }
        if !isEnabled, selectedProviderID == providerID {
            selectProvider("")
        }
        validateAndReconcileSelections()
    }

    /// Whether a model is switched on. Always derived from the persisted
    /// disable list — a view never keeps its own copy, which is what made the
    /// old row refresh only after the selection moved to another model.
    func isModelEnabled(providerID: String, modelID: String) -> Bool {
        !DisabledModelStore.isDisabled(
            providerID: providerID,
            modelID: modelID,
            defaults: defaults
        )
    }

    /// The only path that flips a model switch. Persists the flag, publishes
    /// the catalog revision so the row, the composer and the model menu change
    /// in the same pass, and keeps the selection valid when the model that was
    /// selected is the one being switched off.
    func setModelEnabled(providerID: String, modelID: String, isEnabled: Bool) {
        guard isModelEnabled(providerID: providerID, modelID: modelID) != isEnabled else { return }
        DisabledModelStore.setDisabled(
            !isEnabled,
            providerID: providerID,
            modelID: modelID,
            defaults: defaults
        )
        // A model leaving the catalog is a catalog change: the same revision
        // the provider list already uses, so no view needs its own counter.
        providerCatalogRevision &+= 1
        guard !isEnabled else { return }
        reconcileSelectionAfterModelDisabled(providerID: providerID, modelID: modelID)
    }

    private func reconcileSelectionAfterModelDisabled(providerID: String, modelID: String) {
        guard selectedProviderID == providerID, selectedModel == modelID else { return }
        if let replacement = modelsForSelectedProvider.first {
            // Keep the stored preference: when the model is switched back on it
            // may be restored explicitly, but nothing dead stays selected now.
            selectModel(replacement, persistPreference: false)
        } else {
            selectedModel = ""
            defaults.set("", forKey: "com.mycoder.selectedModel")
        }
    }

    /// Ids of enabled local providers (for send-routing / readiness checks).
    var localProviderIDs: [String] {
        LocalProviderLogic.load().filter { $0.isEnabled }.map { $0.id }
    }

    /// Ids of configured web providers (for send-routing / readiness checks).
    var webProviderIDs: [String] {
        WebProviderStore.load(defaults: defaults).map { $0.id }
    }
}
