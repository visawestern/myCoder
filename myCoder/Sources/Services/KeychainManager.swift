import Foundation

/// Простое хранилище API ключей в UserDefaults — без Keychain, без запросов доступа
final class KeychainManager {
    static let shared = KeychainManager()
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    func saveAPIKey(_ key: String, for providerId: String) throws {
        defaults.set(key, forKey: "api_key_\(providerId)")
    }
    
    func getAPIKey(for providerId: String) throws -> String {
        guard let key = defaults.string(forKey: "api_key_\(providerId)") else {
            throw KeychainError.notFound
        }
        return key
    }
    
    func deleteAPIKey(for providerId: String) throws {
        defaults.removeObject(forKey: "api_key_\(providerId)")
    }
    
    func hasAPIKey(for providerId: String) -> Bool {
        defaults.string(forKey: "api_key_\(providerId)") != nil
    }
    
    func migrateAPIKeysFromPlainStorage(providers: [(id: String, key: String)]) throws {
        for provider in providers {
            try saveAPIKey(provider.key, for: provider.id)
        }
    }
    
    func getAllProviderIDs() -> [String] {
        let dict = defaults.dictionaryRepresentation()
        return dict.keys.compactMap { key in
            guard key.hasPrefix("api_key_") else { return nil }
            return String(key.dropFirst("api_key_".count))
        }
    }
    
    // MARK: - Deprecated (kept for compilation)
    func saveSecret(_ secret: String, identifier: String) throws {
        defaults.set(secret, forKey: "secret_\(identifier)")
    }
    
    func getSecret(identifier: String) throws -> String {
        guard let secret = defaults.string(forKey: "secret_\(identifier)") else {
            throw KeychainError.notFound
        }
        return secret
    }
    
    func deleteSecret(identifier: String) throws {
        defaults.removeObject(forKey: "secret_\(identifier)")
    }
    
    func saveEncryptedData(_ data: Data, identifier: String) throws {
        defaults.set(data, forKey: "encrypted_\(identifier)")
    }
    
    func getEncryptedData(identifier: String) throws -> Data {
        guard let data = defaults.data(forKey: "encrypted_\(identifier)") else {
            throw KeychainError.notFound
        }
        return data
    }
    
    func deleteEncryptedData(identifier: String) throws {
        defaults.removeObject(forKey: "encrypted_\(identifier)")
    }
}

enum KeychainError: Error, LocalizedError {
    case notFound
    case decodingError
    case encodingError
    case saveFailed(status: Int)
    case deleteFailed(status: Int)
    case queryFailed(status: Int)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .decodingError:
            return "Failed to decode data"
        case .encodingError:
            return "Failed to encode data"
        case .saveFailed(let status):
            return "Failed to save (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete (status: \(status))"
        case .queryFailed(let status):
            return "Query failed (status: \(status))"
        }
    }
}
