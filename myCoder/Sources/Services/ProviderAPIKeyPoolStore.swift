import Foundation

/// Persistence for a provider's API-key pool (keychain-backed API keys are
/// per-provider; the pool holds the EXTRA keys beyond `CustomProvider.apiKey`).
/// Stored separately from the provider record so the sensitive material never
/// rides the Codable provider model (which strips the primary key on save).
enum ProviderAPIKeyPoolStore {
    static let storageKey = "com.mycoder.providerAPIKeyPool"
    static let providersKey = "com.mycoder.customProviders"

    /// Pool for one provider (key-indexed list; the primary `apiKey` of the
    /// provider is the implicit first member and is NOT stored here).
    static func load(providerID: String, defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data),
              let pool = map[providerID] else {
            return []
        }
        return pool.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func save(providerID: String, pool: [String], defaults: UserDefaults = .standard) {
        var map: [String: [String]] = [:]
        if let data = defaults.data(forKey: storageKey),
           let existing = try? JSONDecoder().decode([String: [String]].self, from: data) {
            map = existing
        }
        let cleaned = pool.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            map.removeValue(forKey: providerID)
        } else {
            // De-duplicate while preserving order.
            var seen = Set<String>()
            map[providerID] = cleaned.filter { seen.insert($0).inserted }
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func remove(providerID: String, defaults: UserDefaults = .standard) {
        save(providerID: providerID, pool: [], defaults: defaults)
    }
}

/// Loads the custom provider catalog from UserDefaults (keys are stripped on
/// save; the Keychain-backed accessor restores the working key per provider).
/// Used by `QuotaPolicyResolver` so the quota gate works without AppState.
enum CustomProviderCatalogStore {
    static func load(defaults: UserDefaults = .standard) -> [CustomProvider] {
        guard let data = defaults.data(forKey: ProviderAPIKeyPoolStore.providersKey),
              let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) else {
            return []
        }
        return providers
    }
}
