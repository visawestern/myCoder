import Foundation
import SwiftUI
import AppKit

/// Состояние связи с выбранным провайдером.
extension AppState {
    var selectedProviderConnected: Bool {
        // Audit 2026-09-10: this getter runs on EVERY body evaluation
        // (StatusBar, chat input, send readiness) and used to redo JSON
        // decode + model-label regex + cookie-file reads per pass — with a
        // ticking parent that saturates the main thread and starves MainActor
        // API work. Cache briefly: connectivity is session-scoped and flips
        // on minute timescales (login/logout/session expiry), never within
        // seconds, so a 5 s TTL keeps the status dot truthful.
        let now = Date()
        if let cache = providerConnectedCache,
           cache.key == selectedProviderID,
           now.timeIntervalSince(cache.at) < Self.providerConnectedCacheTTL {
            return cache.value
        }
        let value = computeSelectedProviderConnected()
        providerConnectedCache = (key: selectedProviderID, value: value, at: now)
        return value
    }

    /// Invalidate the connectivity cache (call after login/logout/session
    /// capture so the UI reflects the new state immediately).
    func invalidateProviderConnectedCache() {
        providerConnectedCache = nil
    }

    private func computeSelectedProviderConnected() -> Bool {
        let webConnected: Bool?
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            webConnected = WebProviderConnectivity.isConnected(
                config,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        } else {
            webConnected = nil
        }
        let localEnabled = LocalProviderLogic.load().contains {
            $0.id == selectedProviderID && $0.isEnabled
        }
        let customReady = customProviders.contains {
            $0.id == selectedProviderID
                && $0.isEnabled
                && (!$0.requiresAPIKey || !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        return ProviderConnectionStatusLogic.isConnected(
            selectedID: selectedProviderID,
            serverProviderIDs: serverProviders
                .filter { !ProviderEnablementStore.isDisabled($0.id, defaults: defaults) }
                .map(\.id),
            serverConnected: serverConnected,
            webConnected: webConnected,
            localEnabled: localEnabled,
            customReady: customReady,
            remembered: providerConnectivity[selectedProviderID]
        )
    }
}
