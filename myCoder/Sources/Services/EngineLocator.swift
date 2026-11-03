import Foundation

/// Информация о найденной сборке AntiBrowser.
struct AntiBrowserEngineInfo {
    let appURL: URL
    let binaryURL: URL
    let version: String

    var isVerified: Bool { !version.isEmpty }
}

enum EngineLocatorError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "Движок AntiBrowser не найден. Соберите его в ~/AntiBrowser/out156 или добавьте AntiBrowser.app в /Applications."
    }
}

/// Ищет установленную сборку AntiBrowser и проверяет её пригодность.
///
/// Источники поиска (по приоритету):
/// 1. Явный путь из настроек myCoder (UserDefaults `engine.path`).
/// 2. Вложенная AntiBrowser.app в ресурсах приложения.
/// 3. `~/AntiBrowser/out156/Chromium.app` (сборочная дерево).
/// 4. `/Applications/AntiBrowser.app`.
/// 5. `~/Applications/AntiBrowser.app`.
enum EngineLocator {

    /// Пытается найти и проверить движок.
    static func locate() -> AntiBrowserEngineInfo? {
        var candidates: [URL] = []

        if let configured = UserDefaults.standard.string(forKey: "engine.path"), !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured))
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("AntiBrowser.app") {
            candidates.append(bundled)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent("AntiBrowser/out156/Chromium.app"))
        candidates.append(URL(fileURLWithPath: "/Applications/AntiBrowser.app"))
        candidates.append(home.appendingPathComponent("Applications/AntiBrowser.app"))

        for candidate in candidates {
            if let info = verify(candidate) {
                return info
            }
        }
        return nil
    }

    /// Проверяет, что по пути лежит рабочая сборка AntiBrowser, и возвращает
    /// её версию. Не запускает процесс — только бинарь и Info.plist.
    static func verify(_ appURL: URL) -> AntiBrowserEngineInfo? {
        let binary = appURL.appendingPathComponent("Contents/MacOS/Chromium")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            return nil
        }
        let version = readBundleVersion(appURL: appURL) ?? ""
        return AntiBrowserEngineInfo(appURL: appURL, binaryURL: binary, version: version)
    }

    private static func readBundleVersion(appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return dict["CFBundleShortVersionString"] as? String
    }
}
