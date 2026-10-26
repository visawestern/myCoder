import Foundation

/// Persisted enable/disable state for providers that have no native flag of
/// their own (server catalog rows and web providers). Custom and local
/// providers keep using their own `isEnabled` field.
enum ProviderEnablementStore {
    static let storageKey = "com.mycoder.disabledProviders"

    /// Provider ids the user switched off.
    static func disabledIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    static func isDisabled(_ providerID: String, defaults: UserDefaults = .standard) -> Bool {
        disabledIDs(defaults: defaults).contains(providerID)
    }

    static func setDisabled(
        _ disabled: Bool,
        providerID: String,
        defaults: UserDefaults = .standard
    ) {
        var ids = disabledIDs(defaults: defaults)
        if disabled {
            ids.insert(providerID)
        } else {
            ids.remove(providerID)
        }
        if ids.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(ids.sorted(), forKey: storageKey)
        }
        NotificationCenter.default.post(name: .providersChanged, object: nil)
    }

    /// Forget a provider entirely (used when the provider row is deleted).
    static func clear(providerID: String, defaults: UserDefaults = .standard) {
        setDisabled(false, providerID: providerID, defaults: defaults)
    }
}
