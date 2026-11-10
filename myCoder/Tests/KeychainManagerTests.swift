import Foundation
import Testing
@testable import myCoder

/// TDD-набор для аудита A4: KeychainManager должен хранить секреты в
/// НАСТОЯЩЕМ Keychain (Security.framework), а не в UserDefaults; старые
/// UserDefaults-записи читаются как fallback и лениво мигрируются.
///
/// Тесты используют уникальные идентификаторы (UUID), чтобы не трогать
/// реальные ключи пользователя, и всегда подчищают за собой.
@Suite("KeychainManager (A4)")
struct KeychainManagerTests {

    private var manager: KeychainManager { .shared }

    /// Уникальный account для теста (исключает конфликты с реальными данными).
    private func uniqueID(_ prefix: String) -> String {
        "\(prefix)-kc-test-\(UUID().uuidString)"
    }

    @Test("API-ключ round-trip через настоящий Keychain")
    func apiKeyRoundTrip() throws {
        let providerID = uniqueID("api")
        try manager.saveAPIKey("sk-secret-123", for: providerID)
        defer { try? manager.deleteAPIKey(for: providerID) }

        #expect(manager.hasAPIKey(for: providerID))
        #expect(try manager.getAPIKey(for: providerID) == "sk-secret-123")

        try manager.deleteAPIKey(for: providerID)
        #expect(!manager.hasAPIKey(for: providerID))
        #expect(throws: KeychainError.notFound) {
            _ = try manager.getAPIKey(for: providerID)
        }
    }

    @Test("Секрет (пароль провайдера) round-trip")
    func secretRoundTrip() throws {
        let identifier = uniqueID("secret")
        try manager.saveSecret("p@ss", identifier: identifier)
        defer { try? manager.deleteSecret(identifier: identifier) }

        #expect(try manager.getSecret(identifier: identifier) == "p@ss")
        try manager.deleteSecret(identifier: identifier)
        #expect(throws: KeychainError.notFound) {
            _ = try manager.getSecret(identifier: identifier)
        }
    }

    @Test("Старый UserDefaults-ключ мигрирует в Keychain и удаляется")
    func legacyApiKeyMigrates() throws {
        let providerID = uniqueID("legacy")
        let defaultsKey = "api_key_\(providerID)"
        let defaults = UserDefaults.standard
        defaults.set("legacy-key", forKey: defaultsKey)
        defer {
            defaults.removeObject(forKey: defaultsKey)
            try? manager.deleteAPIKey(for: providerID)
        }

        // Первое чтение должно вернуть legacy-значение И перенести его в Keychain.
        #expect(try manager.getAPIKey(for: providerID) == "legacy-key")
        #expect(defaults.object(forKey: defaultsKey) == nil, "после миграции открытая копия должна исчезнуть")
        #expect(manager.hasAPIKey(for: providerID))

        // Повторное чтение идёт уже из Keychain (fallback больше не нужен).
        #expect(try manager.getAPIKey(for: providerID) == "legacy-key")
    }

    @Test("getAllProviderIDs объединяет Keychain и старый UserDefaults")
    func allProviderIDsUnion() throws {
        let legacyID = uniqueID("union-legacy")
        let keychainID = uniqueID("union-keychain")
        let defaults = UserDefaults.standard
        defaults.set("legacy", forKey: "api_key_\(legacyID)")
        try manager.saveAPIKey("keychain", for: keychainID)
        defer {
            defaults.removeObject(forKey: "api_key_\(legacyID)")
            try? manager.deleteAPIKey(for: keychainID)
            try? manager.deleteAPIKey(for: legacyID)
        }

        let all = manager.getAllProviderIDs()
        #expect(all.contains(legacyID))
        #expect(all.contains(keychainID))
    }
}
