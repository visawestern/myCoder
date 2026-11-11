import SwiftUI

extension ModelSettingsProviderColumns {
    var options: [ProviderOption] {
        appState.manageableProviderOptions
    }

    func webConfig(for providerID: String) -> WebProviderConfig? {
        guard let id = WebProviderConnectivity.configID(fromOptionID: providerID) else { return nil }
        return WebProviderStore.load().first(where: { $0.id == id })
    }

    func isMutableProvider(_ option: ProviderOption) -> Bool {
        option.isCustom || localProvider(for: option.id) != nil || webConfig(for: option.id) != nil
    }

    func localProvider(for providerID: String) -> LocalProviderConfig? {
        LocalProviderLogic.load().first(where: { $0.id == providerID })
    }

    func customProvider(for providerID: String) -> CustomProvider? {
        appState.customProviders.first(where: { $0.id == providerID })
    }

    func isProviderEnabled(_ option: ProviderOption) -> Bool {
        appState.isProviderEnabled(option.id)
    }

    func setProviderEnabled(_ option: ProviderOption, enabled: Bool) {
        appState.setProviderEnabled(option.id, isEnabled: enabled)
    }

    func isRenameableProvider(_ option: ProviderOption) -> Bool {
        isMutableProvider(option)
    }

    func commitProviderName(_ option: ProviderOption) {
        let trimmed = providerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerNameDraft = option.name
            return
        }
        guard trimmed != option.name else { return }
        if let index = appState.customProviders.firstIndex(where: { $0.id == option.id }) {
            var updated = appState.customProviders[index]
            updated.name = trimmed
            appState.updateCustomProvider(updated)
            return
        }
        if var local = localProvider(for: option.id) {
            local.name = trimmed
            LocalProviderLogic.update(local)
            return
        }
        if let web = webConfig(for: option.id) {
            var configs = WebProviderStore.load()
            guard let index = configs.firstIndex(where: { $0.id == web.id }) else { return }
            configs[index].displayName = trimmed
            WebProviderStore.save(configs)
        }
    }

    func commitCustomProviderDraft(_ providerID: String) {
        guard let index = appState.customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var updated = appState.customProviders[index]
        let url = customBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = customAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url != updated.baseURL || key != (updated.getSecureAPIKey() ?? "") else { return }
        updated.baseURL = url
        updated.apiKey = key
        appState.updateCustomProvider(updated)
    }

    func commitLocalProviderDraft(_ providerID: String) {
        guard var local = localProvider(for: providerID) else { return }
        let host = localHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(localPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? local.port
        guard !host.isEmpty, host != local.host || port != local.port else { return }
        local.host = host
        local.port = port
        LocalProviderLogic.update(local)
    }

    func refreshProvider(_ option: ProviderOption) {
        localRefreshMessage = nil
        if let custom = customProvider(for: option.id) {
            appState.refreshModels(for: custom.id)
            return
        }
        if let local = localProvider(for: option.id) {
            Task {
                await appState.refreshLocalModels(local.id)
                await MainActor.run {
                    let refreshed = localProvider(for: option.id)
                    localRefreshMessage = refreshed.map {
                        L.t(AppLocalizationKey.locModelsCount, $0.models.count)
                    }
                }
            }
            return
        }
        if let web = webConfig(for: option.id) {
            Task {
                let message = await appState.refreshWebModels(for: web)
                await MainActor.run { localRefreshMessage = message }
            }
        }
    }

    func selectProvider(_ option: ProviderOption) {
        detailProviderID = option.id
        guard isProviderEnabled(option) else { return }
        appState.selectProvider(option.id)
    }

    func removeProvider(_ option: ProviderOption) {
        if let custom = customProvider(for: option.id) {
            appState.removeCustomProvider(custom)
            DisabledModelStore.clear(providerID: custom.id)
            return
        }
        if let local = localProvider(for: option.id) {
            LocalProviderLogic.remove(id: local.id)
            DisabledModelStore.clear(providerID: local.id)
            if appState.selectedProviderID == option.id { appState.selectProvider("") }
            return
        }
        if let web = webConfig(for: option.id) {
            var configs = WebProviderStore.load()
            configs.removeAll { $0.id == web.id }
            WebProviderStore.save(configs)
            try? WebSessionManager.clear(providerId: web.id,
                                         homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            if appState.selectedProviderID == option.id { appState.selectProvider("") }
        }
    }

    func canDeleteModels(providerID: String) -> Bool {
        customProvider(for: providerID) != nil || localProvider(for: providerID) != nil
    }

    func deleteModel(_ modelID: String, from providerID: String) {
        if customProvider(for: providerID) != nil {
            appState.removeModel(modelID, from: providerID)
            return
        }
        guard localProvider(for: providerID) != nil else { return }
        LocalProviderLogic.removeModel(modelID, from: providerID)
    }

    func isModelDisabled(_ modelID: String, providerID: String) -> Bool {
        !appState.isModelEnabled(providerID: providerID, modelID: modelID)
    }

    /// Delegates to the single mutation path in `AppState`: the store is
    /// updated, the catalog revision is published and the selection is kept
    /// valid. The row itself holds no copy of the flag.
    func toggleModelDisabled(_ modelID: String, providerID: String, enabled: Bool? = nil) {
        // Without an explicit value the switch flips: a disabled row becomes
        // enabled. Both the row toggle and the menu use this one path.
        let newValue = enabled ?? isModelDisabled(modelID, providerID: providerID)
        appState.setModelEnabled(
            providerID: providerID,
            modelID: modelID,
            isEnabled: newValue
        )
    }

    func isEditingModel(modelID: String, providerID: String) -> Bool {
        editingModelProviderID == providerID && editingModelID == modelID
    }

    func beginRename(_ modelID: String, providerID: String) {
        editingModelProviderID = providerID
        editingModelID = modelID
        editingModelDraft = modelID
    }

    func beginClone(_ modelID: String, providerID: String) {
        cloneModelProviderID = providerID
        cloneSourceModelID = modelID
        cloneModelDraft = modelID + "-copy"
    }

    func cancelRename() {
        editingModelProviderID = ""
        editingModelID = ""
        editingModelDraft = ""
    }

    func commitRename(modelID: String, providerID: String) {
        let renamed = editingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        guard !renamed.isEmpty, renamed != modelID else { return }
        appState.renameCustomModel(providerID: providerID, modelID: modelID, to: renamed)
    }

    func commitClone(sourceModelID: String, providerID: String) {
        let name = cloneModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        cloneSourceModelID = ""
        cloneModelProviderID = ""
        cloneModelDraft = ""
        guard !name.isEmpty, name != sourceModelID else { return }
        appState.cloneCustomModel(providerID: providerID, modelID: sourceModelID, newName: name)
    }

    func commitAddModel(providerID: String) {
        let id = newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        newModelDraft = ""
        newModelProviderID = ""
        guard !id.isEmpty else { return }
        appState.addCustomModel(providerID: providerID, modelID: id)
    }

    func isEditingClone(modelID: String, providerID: String) -> Bool {
        cloneModelProviderID == providerID && cloneSourceModelID == modelID
    }

    func models(for providerID: String) -> [String] {
        if let web = webConfig(for: providerID) {
            return WebProviderConnectivity.models(for: web)
        }
        if let local = localProvider(for: providerID) {
            return local.models
        }
        if let custom = customProvider(for: providerID) {
            return custom.models.sorted()
        }
        return ProviderSettingsLogic.models(
            for: providerID,
            in: appState.serverProviders,
            customProviders: appState.customProviders
        )
    }
}
