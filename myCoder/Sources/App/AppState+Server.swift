import Foundation
import SwiftUI
import AppKit

/// Подключение к локальному серверу и его каталоги.
extension AppState {
    /// The server connection is opt-in: the app never connects to a local
    /// agent on its own, because that agent's provider catalog would show up
    /// as providers the user never added.
    static func serverConnectionEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "com.mycoder.serverConnectionEnabled")
    }

    func migrateLegacyPreferences() {
        let rawAccess = defaults.string(forKey: "com.mycoder.accessLevel") ?? ""
        if AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: rawAccess) {
            agentMode = .plan
            defaults.set(AgentMode.plan.rawValue, forKey: "com.mycoder.agentMode")
            defaults.set(AccessLevel.askBeforeChanges.rawValue, forKey: "com.mycoder.accessLevel")
        }

        // The legacy anonymous provider was renamed after its Xiaomi channel sunset.
        // Preserve an existing explicit selection across the rename.
        for key in ["com.mycoder.selectedProviderID", "com.mycoder.preferredProviderID"] {
            let value = defaults.string(forKey: key)
            if value == "mimo-auto" {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func connectToServer() async {
        // The startup probe runs only for an explicitly enabled connection.
        // Without it the app stays offline until the user connects from the
        // Remote connection sheet — no foreign provider catalog appears.
        guard Self.serverConnectionEnabled(defaults: defaults) else {
            await MainActor.run {
                self.serverConnected = false
            }
            return
        }
        // Complete the health check before deciding whether server-backed
        // models may load. Previously the manager became connected while this
        // AppState boolean stayed false, so ContentView skipped model loading
        // on a healthy server during the first startup task.
        await serverConnectionManager?.checkAvailability()
        let managerConnected = serverConnectionManager?.isConnected == true
        let newServerConnected = ServerConnectionReadinessLogic.appStateConnectionState(
            isConnected: serverConnected,
            healthHealthy: managerConnected
        )
        await MainActor.run {
            serverConnected = newServerConnected
        }

        if serverConnected {
            await syncAccessLevelFromServer()
        }
    }

    func loadSessionsFromServer() async {
        // Sessions come from the local DB, then optionally from a server the
        // user is already running on localhost. We NEVER spawn a `mimo` CLI or
        // launch `mimo serve` ourselves — the app is fully decoupled from MiMo.
        // 1. Load from the local database.
        await loadProjectsFromDatabase()

        // 2. Optionally sync with a server if the user has one running.
        if serverConnectionManager?.isConnected == true {
            let adapter = ServerToLocalMigrationAdapter(client: mimoClient)
            if let workspace = selectedWorkspace {
                let syncedSessions = await adapter.loadSessions(projectId: workspace.id)
                await MainActor.run {
                    if !syncedSessions.isEmpty {
                        // Audit 2026-09-09: never wipe standalone chats on
                        // server sync (same loss as the project-DB load).
                        // Sourced from the database — the in-memory list may
                        // be mid-reload when the sync lands.
                        let storedStandalone = DatabaseBridge.shared.loadStandaloneSessions()
                        let standalone = storedStandalone.filter { stored in
                            !syncedSessions.contains(where: { synced in synced.id == stored.id })
                        }
                        self.sessions = syncedSessions + standalone
                    }
                }
            }
        }
    }

    func loadModelsFromServer() async {
        do {
            let providers = try await mimoClient.providers()
            await MainActor.run {
                self.serverProviders = providers
                ServerProviderCatalogStore.save(providers, defaults: self.defaults)
                self.validateAndReconcileSelections()
            }
        } catch {
            print("Failed to load models: \(error)")
        }
    }
}
