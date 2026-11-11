import Foundation
import SwiftUI
import AppKit

/// Свои провайдеры и их модели.
extension AppState {
    
    func setCustomProviderEnabled(_ providerID: String, isEnabled: Bool) {
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        customProviders[index].isEnabled = isEnabled
        saveCustomProviders()
        if isEnabled {
            loadModelsFromCustomProvider(customProviders[index])
        }
        validateAndReconcileSelections()
    }

    func addCustomProvider(_ provider: CustomProvider) {
        // Save API key to Keychain and clear plain storage before saving to UserDefaults
        if !provider.apiKey.isEmpty {
            DatabaseBridge.shared.saveProviderAPIKey(providerId: provider.id, apiKey: provider.apiKey)
        }
        var cleanProvider = provider
        // In-memory copy keeps the working key (restored from Keychain) so
        // send-readiness validation sees the truth — the plain-key strip only
        // matters for the UserDefaults serialization below. Without this, a
        // freshly added/edited provider blocks sending with "requires an API
        // key" until the app restarts (audit ARCH-04).
        cleanProvider.apiKey = provider.apiKey.isEmpty
            ? (DatabaseBridge.shared.getProviderAPIKey(providerId: provider.id) ?? "")
            : provider.apiKey
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = cleanProvider
        } else {
            customProviders.append(cleanProvider)
        }
        saveCustomProviders()
        if provider.isEnabled {
            loadModelsFromCustomProvider(provider)
        }
    }

    func removeCustomProvider(_ provider: CustomProvider) {
        DatabaseBridge.shared.deleteProviderAPIKey(providerId: provider.id)
        ProviderEnablementStore.clear(providerID: provider.id, defaults: defaults)
        customProviders.removeAll { $0.id == provider.id }
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    func updateCustomProvider(_ updated: CustomProvider) {
        guard let index = customProviders.firstIndex(where: { $0.id == updated.id }) else { return }
        // Save API key to Keychain and clear plain storage
        if !updated.apiKey.isEmpty {
            DatabaseBridge.shared.saveProviderAPIKey(providerId: updated.id, apiKey: updated.apiKey)
        }
        var cleanProvider = updated
        // Same ARCH-04 fix as addCustomProvider: the in-memory copy must
        // reflect the Keychain-resident key so readiness checks pass and the
        // OpenAI-compatible send route can resolve it without a restart.
        cleanProvider.apiKey = updated.apiKey.isEmpty
            ? (DatabaseBridge.shared.getProviderAPIKey(providerId: updated.id) ?? "")
            : updated.apiKey
        customProviders[index] = cleanProvider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    /// Rename a custom provider's model in place. The new id becomes a manual
    /// entry and the old one is hidden, so a catalog refresh merges cleanly
    /// instead of reverting the rename to the server-side list.
    func renameCustomModel(providerID: String, modelID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != modelID else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        provider.customModels.removeAll { $0 == modelID }
        if !provider.hiddenModels.contains(modelID) {
            provider.hiddenModels.append(modelID)
        }
        if !provider.customModels.contains(trimmed) {
            provider.customModels.append(trimmed)
        }
        provider.models = provider.models.map { $0 == modelID ? trimmed : $0 }
        if !provider.models.contains(trimmed) {
            provider.models.append(trimmed)
        }
        customProviders[index] = provider
        saveCustomProviders()
        if selectedProviderID == providerID && selectedModel == modelID {
            selectedModel = trimmed
            defaults.set(trimmed, forKey: "com.mycoder.selectedModel")
            defaults.set(trimmed, forKey: "com.mycoder.preferredModelID")
        }
        validateAndReconcileSelections()
    }

    /// Clone a model entry under a new id (manual entry, survives refresh).
    func cloneCustomModel(providerID: String, modelID: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != modelID else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        guard !provider.models.contains(trimmed) else { return }
        provider.customModels.append(trimmed)
        provider.hiddenModels.removeAll { $0 == trimmed }
        provider.models.append(trimmed)
        customProviders[index] = provider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    /// Add a fully custom model id that the provider's catalog may not list.
    func addCustomModel(providerID: String, modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        guard !provider.models.contains(trimmed) else { return }
        provider.customModels.append(trimmed)
        provider.hiddenModels.removeAll { $0 == trimmed }
        provider.models.append(trimmed)
        customProviders[index] = provider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    func testProvider(url: String, apiKey: String, type: ProviderType) async -> Bool {
        guard let modelsURLString = ProviderEndpointLogic.modelsURL(for: url),
              let testURL = URL(string: modelsURLString) else { return false }
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 10
        
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: http.statusCode, body: data)
        } catch {
            return false
        }
    }

    func refreshModels(for providerID: String) {
        guard let provider = customProviders.first(where: { $0.id == providerID }) else { return }
        loadModelsFromCustomProvider(provider)
    }

    /// Background refresh of a local provider's model list (fetch → persist →
    /// reconcile selection). Never wipes: failed/empty fetch keeps everything
    /// as-is with an honest status message. `fetch` is injectable for tests.
    /// All state mutations hop to MainActor: @Published writes from a
    /// background task abort the app via AppKit menu assertions (crash
    /// 2026-10-15, `providerModelLoadMessages.modify` off-main).
    func refreshLocalModels(
        _ providerID: String,
        fetch: @escaping (LocalProviderConfig) async -> [String]? = { await LocalProviderLogic.fetchModels(for: $0) }
    ) async {
        let locals = LocalProviderLogic.load(defaults: defaults)
        guard let config = locals.first(where: { $0.id == providerID && $0.isEnabled }) else { return }
        let fresh = await fetch(config)
        await MainActor.run {
            guard let fresh, !fresh.isEmpty else {
                self.providerModelLoadMessages[providerID] =
                    "Could not refresh models from \(config.serveBaseURL). Check the server and credentials; keeping existing list."
                return
            }
            var updated = LocalProviderLogic.load(defaults: self.defaults)
            if let idx = updated.firstIndex(where: { $0.id == providerID }) {
                updated[idx].models = fresh
                LocalProviderLogic.save(updated, defaults: self.defaults)
            }
            if self.selectedProviderID == providerID {
                let next = LocalModelRefreshLogic.reconcile(current: self.selectedModel, fresh: fresh)
                if next != self.selectedModel {
                    self.selectedModel = next
                    self.defaults.set(next, forKey: "com.mycoder.selectedModel")
                }
            }
            self.providerModelLoadMessages[providerID] = "Loaded \(fresh.count) model\(fresh.count == 1 ? "" : "s") from \(config.serveBaseURL)."
        }
    }

    func removeModel(_ modelID: String, from providerID: String) {
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        customProviders[index].models.removeAll { $0 == modelID }
        customProviders[index].customModels.removeAll { $0 == modelID }
        if !customProviders[index].hiddenModels.contains(modelID) {
            customProviders[index].hiddenModels.append(modelID)
        }
        saveCustomProviders()
        if selectedProviderID == providerID && selectedModel == modelID {
            selectedModel = customProviders[index].models.first ?? ""
            defaults.set(selectedModel, forKey: "com.mycoder.selectedModel")
            defaults.set(selectedModel, forKey: "com.mycoder.preferredModelID")
            selectedVariant = ""
        }
        validateAndReconcileSelections()
    }

    func providerModelLoadMessage(for providerID: String) -> String? {
        providerModelLoadMessages[providerID]
    }

    func loadModelsFromCustomProvider(_ provider: CustomProvider) {
        // Custom providers are stored locally and merged into the picker only.
        // MiMo Serve reads provider credentials from mimocode.json on disk; this
        // app does not push custom provider config to the server API.
        Task {
            let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: trimmedBaseURL.hasSuffix("/models")
                                ? trimmedBaseURL
                                : "\(trimmedBaseURL)/models") else {
                await MainActor.run {
                    self.providerModelLoadMessages[provider.id] = "Invalid provider URL."
                }
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // Use Keychain-backed API key if available, fall back to plain storage
            let apiKey = provider.getSecureAPIKey() ?? ""
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "Model request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)): \(String(body.prefix(180)))"
                    }
                    return
                }
                guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "The provider returned an invalid model-list response."
                    }
                    return
                }
                // OpenAI-compatible: { data: [{ id }] }; Ollama: { models:
                // [{ name }] }; Google: { models: [{ name: "models/..." }] }.
                // Keep refresh and Test Connection on one canonical parser so
                // blank IDs, fallback names, and duplicate rows behave alike.
                let discoveredModels = ProviderConnectionValidationLogic.modelIDs(from: data)
                let models: [String] = discoveredModels
                guard !models.isEmpty else {
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "No models were found in this provider's response. Check its API base URL."
                    }
                    return
                }
                let providerID = provider.id
                let loadedModels = models
                let modelCount = loadedModels.count
                let modelLoadMessage = "Loaded \(modelCount) model\(modelCount == 1 ? "" : "s")."
                await MainActor.run { [providerID, loadedModels, modelLoadMessage] in
                    if let index = customProviders.firstIndex(where: { $0.id == providerID }) {
                        customProviders[index].models = CustomModelListLogic.mergedModels(
                            provider: customProviders[index],
                            discovered: loadedModels
                        )
                        saveCustomProviders()
                    }
                    providerModelLoadMessages[providerID] = modelLoadMessage
                    if selectedProviderID == providerID || selectedProviderID.isEmpty {
                        validateAndReconcileSelections()
                    }
                }
            } catch {
                await MainActor.run {
                    self.providerModelLoadMessages[provider.id] = "Could not load models: \(error.localizedDescription)"
                }
            }
        }
    }

    func saveCustomProviders() {
        // Strip apiKey fields before saving to UserDefaults — keys live in Keychain
        let cleanProviders = customProviders.map { provider -> CustomProvider in
            var clean = provider
            clean.apiKey = ""
            return clean
        }
        if let data = try? JSONEncoder().encode(cleanProviders) {
            defaults.set(data, forKey: "com.mycoder.customProviders")
        }
        NotificationCenter.default.post(name: .providersChanged, object: nil)
    }
}
