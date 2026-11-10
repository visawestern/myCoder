import Foundation
import Security

/// Настоящее хранилище секретов в macOS Keychain (audit A4). Раньше класс
/// назывался KeychainManager, но писал в UserDefaults — секреты лежали в
/// открытом виде в plist. Теперь значения хранятся в Keychain через
/// Security.framework; старые записи UserDefaults читаются как fallback и
/// лениво мигрируются (переносятся в Keychain и удаляются из UserDefaults).
final class KeychainManager {
    static let shared = KeychainManager()

    /// Service-идентификатор для всех элементов этого приложения.
    private let service = "com.mycoder.keychain"

    /// Старое (устаревшее) хранилище — только для миграции/чтения.
    private let defaults = UserDefaults.standard

    private init() {}

    /// MARK: - Низкоуровневый Keychain API

    /// Пишет строку в Keychain для `account`.
    ///
    /// Вход: значение, идентификатор учётной записи. Выход: throws при
    /// ошибке Security framework. Зависимости: SecItemAdd/SecItemUpdate.
    private func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(status: Int(addStatus))
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: Int(status))
        }
    }

    /// Читает строку из Keychain для `account`; nil, если элемента нет.
    ///
    /// Вход: идентификатор учётной записи. Выход: значение или nil.
    /// Зависимости: SecItemCopyMatching.
    private func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Удаляет элемент из Keychain для `account` (idempotентно).
    ///
    /// Вход: идентификатор учётной записи. Выход: throws при ошибке.
    /// Зависимости: SecItemDelete.
    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: Int(status))
        }
    }

    /// Есть ли элемент в Keychain для `account`.
    private func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// MARK: - API-ключи провайдеров

    func saveAPIKey(_ key: String, for providerId: String) throws {
        try set(key, account: "api_key_\(providerId)")
        // После успешной записи в Keychain удаляем старую открытую копию.
        defaults.removeObject(forKey: "api_key_\(providerId)")
    }

    /// Читает API-ключ: сначала Keychain, затем (для миграции) UserDefaults;
    /// при находке в UserDefaults — переносит в Keychain и удаляет оттуда.
    ///
    /// Вход: id провайдера. Выход: ключ или throw .notFound.
    /// Зависимости: `get(account:)`, `set(_:account:)`, `delete(account:)`.
    func getAPIKey(for providerId: String) throws -> String {
        if let key = get(account: "api_key_\(providerId)") {
            return key
        }
        guard let legacy = defaults.string(forKey: "api_key_\(providerId)") else {
            throw KeychainError.notFound
        }
        // Ленивая миграция: переносим в Keychain, удаляем открытую копию.
        try? set(legacy, account: "api_key_\(providerId)")
        defaults.removeObject(forKey: "api_key_\(providerId)")
        return legacy
    }

    func deleteAPIKey(for providerId: String) throws {
        try delete(account: "api_key_\(providerId)")
        defaults.removeObject(forKey: "api_key_\(providerId)")
    }

    func hasAPIKey(for providerId: String) -> Bool {
        exists(account: "api_key_\(providerId)")
            || defaults.string(forKey: "api_key_\(providerId)") != nil
    }

    /// Мигрирует ключи из «обычного» (дополнительного) источника в Keychain.
    func migrateAPIKeysFromPlainStorage(providers: [(id: String, key: String)]) throws {
        for provider in providers {
            try saveAPIKey(provider.key, for: provider.id)
        }
    }

    /// Все id провайдеров, у которых есть ключ (Keychain + старый UserDefaults).
    func getAllProviderIDs() -> [String] {
        var ids = Set<String>()
        // 1) Keychain: перечисляем элементы сервиса.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
           let array = items as? [[String: Any]] {
            for item in array {
                if let account = item[kSecAttrAccount as String] as? String,
                   account.hasPrefix("api_key_") {
                    ids.insert(String(account.dropFirst("api_key_".count)))
                }
            }
        }
        // 2) Старый UserDefaults (миграция ещё не завершена).
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("api_key_") {
            ids.insert(String(key.dropFirst("api_key_".count)))
        }
        return Array(ids).sorted()
    }

    // MARK: - Deprecated-секреты (пароли локальных провайдеров и пр.)

    /// Сохраняет произвольный секрет (например, пароль провайдера) в Keychain.
    func saveSecret(_ secret: String, identifier: String) throws {
        try set(secret, account: "secret_\(identifier)")
        defaults.removeObject(forKey: "secret_\(identifier)")
    }

    /// Читает секрет (Keychain → UserDefaults-fallback с миграцией).
    func getSecret(identifier: String) throws -> String {
        if let secret = get(account: "secret_\(identifier)") {
            return secret
        }
        guard let legacy = defaults.string(forKey: "secret_\(identifier)") else {
            throw KeychainError.notFound
        }
        try? set(legacy, account: "secret_\(identifier)")
        defaults.removeObject(forKey: "secret_\(identifier)")
        return legacy
    }

    func deleteSecret(identifier: String) throws {
        try delete(account: "secret_\(identifier)")
        defaults.removeObject(forKey: "secret_\(identifier)")
    }

    func saveEncryptedData(_ data: Data, identifier: String) throws {
        let base64 = data.base64EncodedString()
        try set(base64, account: "encrypted_\(identifier)")
        defaults.removeObject(forKey: "encrypted_\(identifier)")
    }

    func getEncryptedData(identifier: String) throws -> Data {
        if let base64 = get(account: "encrypted_\(identifier)"),
           let data = Data(base64Encoded: base64) {
            return data
        }
        guard let legacy = defaults.data(forKey: "encrypted_\(identifier)") else {
            throw KeychainError.notFound
        }
        try? set(legacy.base64EncodedString(), account: "encrypted_\(identifier)")
        defaults.removeObject(forKey: "encrypted_\(identifier)")
        return legacy
    }

    func deleteEncryptedData(identifier: String) throws {
        try delete(account: "encrypted_\(identifier)")
        defaults.removeObject(forKey: "encrypted_\(identifier)")
    }
}

enum KeychainError: Error, LocalizedError, Equatable {
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
