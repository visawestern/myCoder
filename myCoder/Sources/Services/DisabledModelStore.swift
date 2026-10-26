import Foundation

enum DisabledModelStore {
    static let storageKey = "com.mycoder.disabledModels"

    static func disabledModels(for providerID: String, defaults: UserDefaults = .standard) -> Set<String> {
        guard let stored = defaults.dictionary(forKey: storageKey) as? [String: [String]] else { return [] }
        return Set(stored[providerID] ?? [])
    }

    static func isDisabled(providerID: String, modelID: String, defaults: UserDefaults = .standard) -> Bool {
        disabledModels(for: providerID, defaults: defaults).contains(modelID)
    }

    static func setDisabled(
        _ disabled: Bool,
        providerID: String,
        modelID: String,
        defaults: UserDefaults = .standard
    ) {
        var stored = defaults.dictionary(forKey: storageKey) as? [String: [String]] ?? [:]
        var models = Set(stored[providerID] ?? [])
        if disabled {
            models.insert(modelID)
        } else {
            models.remove(modelID)
        }
        if models.isEmpty {
            stored.removeValue(forKey: providerID)
        } else {
            stored[providerID] = Array(models).sorted()
        }
        if stored.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(stored, forKey: storageKey)
        }
    }

    static func clear(providerID: String, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: storageKey) as? [String: [String]] ?? [:]
        stored.removeValue(forKey: providerID)
        if stored.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(stored, forKey: storageKey)
        }
    }
}
