import Foundation
import SwiftUI
import AppKit

/// Режим встроенного сервера.
extension AppState {
    func loadCustomProviders() {
        if let data = defaults.data(forKey: "com.mycoder.customProviders"),
           let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) {
            customProviders = providers
            // Restore apiKey from Keychain for any provider that has been migrated
            for i in customProviders.indices {
                if customProviders[i].apiKey.isEmpty {
                    if let keychainKey = DatabaseBridge.shared.getProviderAPIKey(providerId: customProviders[i].id) {
                        customProviders[i].apiKey = keychainKey
                    }
                }
            }
            let deduplicated = ProviderDuplicationLogic.removingDuplicates(customProviders)
            if deduplicated.count != customProviders.count {
                for removed in customProviders where !deduplicated.contains(where: { $0.id == removed.id }) {
                    DatabaseBridge.shared.deleteProviderAPIKey(providerId: removed.id)
                }
                customProviders = deduplicated
                saveCustomProviders()
            }
        }
        for provider in customProviders where provider.isEnabled {
            loadModelsFromCustomProvider(provider)
        }
        validateAndReconcileSelections()
    }

    func connectToServe(hostname: String, port: Int) async {
        let newClient = MimoServeClient(host: hostname, port: port)
        
        await MainActor.run {
            self.serverHost = hostname
            self.serverPort = port
            self.mimoClient = newClient
            ServerProviderCatalogStore.saveConnection(host: hostname, port: port, defaults: self.defaults)
            // An explicit connection opts into the startup probe from now on.
            self.defaults.set(true, forKey: "com.mycoder.serverConnectionEnabled")
        }
        
        do {
            let health = try await newClient.health()
            await MainActor.run {
                self.serverConnected = health.healthy
                if health.healthy {
                    self.notificationService.serverConnected()
                }
            }
            if health.healthy {
                await loadModelsFromServer()
                await syncAccessLevelFromServer()
            }
        } catch {
            MyCoderAPIServer.appendLog("Connection failed: \(error)")
            await MainActor.run {
                self.serverConnected = false
                self.notificationService.serverDisconnected()
            }
        }
    }

    func stopServe() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.serverConnected = false
            self.notificationService.serverDisconnected()
            self.serverProviders = []
            // Disconnecting also drops the opt-in for the startup probe.
            self.defaults.set(false, forKey: "com.mycoder.serverConnectionEnabled")
            ServerProviderCatalogStore.save([], defaults: self.defaults)
            if !self.customProviders.contains(where: { $0.id == self.selectedProviderID && $0.isEnabled }) {
                if let firstCustom = self.customProviders.first(where: { $0.isEnabled }) {
                    self.selectProvider(firstCustom.id)
                } else {
                    self.selectedProviderID = ""
                    self.selectedModel = ""
                    self.selectedVariant = ""
                    self.defaults.set("", forKey: "com.mycoder.selectedProviderID")
                    self.defaults.set("", forKey: "com.mycoder.selectedModel")
                }
            } else {
                self.validateAndReconcileSelections()
            }
        }
    }
}
