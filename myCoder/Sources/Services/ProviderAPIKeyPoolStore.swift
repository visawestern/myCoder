import Foundation

/// Persistence for a provider's API-key pool (extra keys beyond the primary
/// `CustomProvider.apiKey`). Stored separately from the provider record so the
/// sensitive material never rides the Codable provider model.
///
/// Input: provider id + a list of keys + a UserDefaults domain.
/// Output: ordered, deduplicated, non-blank key list.
/// Dependencies: `UserDefaults` only.
enum ProviderAPIKeyPoolStore {
    static let storageKey = "com.mycoder.providerAPIKeyPool"
    /// Domain key that holds the custom-provider catalog (read-only use here).
    static let providersKey = "com.mycoder.customProviders"

    /// Load one provider's extra keys; the primary key is NOT stored here.
    ///
    /// Input: provider id, defaults domain.
    /// Output: ordered non-blank pool keys (empty when none configured).
    /// Dependencies: `UserDefaults`.
    static func load(providerID: String, defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data),
              let pool = map[providerID] else {
            return []
        }
        return pool.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Save one provider's pool: blank entries dropped, duplicates removed,
    /// order preserved paving the primary key first as written by the caller.
    ///
    /// Input: provider id, keys, defaults domain.
    /// Output: none (writes to storage).
    /// Dependencies: `UserDefaults`.
    static func save(providerID: String, pool: [String], defaults: UserDefaults = .standard) {
        var map: [String: [String]] = [:]
        if let data = defaults.data(forKey: storageKey),
           let existing = try? JSONDecoder().decode([String: [String]].self, from: data) {
            map = existing
        }
        let cleaned = pool
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = cleaned.filter { seen.insert($0).inserted }
        if unique.isEmpty {
            map.removeValue(forKey: providerID)
        } else {
            map[providerID] = unique
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Remove a provider's pool entirely.
    ///
    /// Input: provider id, defaults domain. Output: none. Dependencies: `save`.
    static func remove(providerID: String, defaults: UserDefaults = .standard) {
        save(providerID: providerID, pool: [], defaults: defaults)
    }
}

/// Read-only access to the custom provider catalog from UserDefaults. API keys
/// are stripped on save; `getSecureAPIKey()` restores the working key.
///
/// Input: defaults domain.
/// Output: decoded providers (empty when absent or corrupt).
/// Dependencies: `CustomProvider`, `UserDefaults`.
enum CustomProviderCatalogStore {
    static func load(defaults: UserDefaults = .standard) -> [CustomProvider] {
        guard let data = defaults.data(forKey: ProviderAPIKeyPoolStore.providersKey),
              let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) else {
            return []
        }
        return providers
    }
}
