import Foundation

/// Менеджер мостов чатов: один движок AntiBrowser, один мост (REST) на чат.
/// Повторный вход в тот же чат возвращает тот же мост: браузер хранит
/// вкладку по ключу (`tab_key`) и переиспользует её — копий браузера и
/// вкладок не плодится.
@MainActor
final class AntiBrowserTabManager {

    static let shared = AntiBrowserTabManager()

    /// Единый ключ вкладки/моста для чата (совпадает с tab_key браузера).
    static func makeKey(providerID: String, projectID: String, chatID: String) -> String {
        "\(providerID)|\(projectID)|\(chatID)"
    }

    /// Стандартный путь профиля движка. Используется, пока EngineStatusCenter
    /// ещё не настроил менеджер (ленивый старт: первый мост до запуска
    /// движка уже должен знать, где профиль, чтобы поднять его).
    static func defaultProfileDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyCoder/AntiBrowserProfile")
    }

    private var bridges: [String: AntiBrowserAutomationBridge] = [:]
    private var apiPort = 5390
    private var profileDir: URL?

    private init() {}

    /// Устанавливает конфигурацию после готовности движка.
    func configure(apiPort: Int, profileDir: URL) {
        self.apiPort = apiPort
        self.profileDir = profileDir
        // Мосты, созданные до готовности движка (пустой токен), тоже
        // получают актуальные порт и профиль.
        for bridge in bridges.values {
            bridge.configure(apiPort: apiPort, profileDir: profileDir)
        }
    }

    /// Возвращает (создавая при необходимости) мост для ключа чата.
    func bridge(tabKey: String) -> AntiBrowserAutomationBridge {
        let key = tabKey.isEmpty ? "default" : tabKey
        if let existing = bridges[key] {
            return existing
        }
        // До конфигурации EngineStatusCenter используем стандартный профиль,
        // чтобы первый REST-запрос мог лениво поднять движок.
        let bridge = AntiBrowserAutomationBridge(
            tabKey: key,
            apiPort: apiPort,
            profileDir: profileDir ?? Self.defaultProfileDir())
        bridges[key] = bridge
        return bridge
    }

    func release(key: String) {
        bridges.removeValue(forKey: key.isEmpty ? "default" : key)
    }

    func releaseAll() {
        bridges.removeAll()
    }

    /// Все активные мосты (ключ → мост) для диагностики/API.
    func allBridges() -> [(key: String, bridge: AntiBrowserAutomationBridge)] {
        bridges.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
}
