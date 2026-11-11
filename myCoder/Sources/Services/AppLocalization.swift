import Foundation

enum AppLocalization {
    static func string(forEnglish english: String, language: AppLanguage) -> String {
        if let key = translations.first(where: { $0.value["en"] == english }).flatMap({ AppLocalizationKey(rawValue: $0.key) }) {
            return string(key, language: language)
        }
        return english
    }

    static func string(_ key: AppLocalizationKey, language: AppLanguage) -> String {
        guard let entry = translations[key.rawValue] else { return key.rawValue }
        switch language {
        case .english: return entry["en"] ?? key.rawValue
        case .russian: return entry["ru"] ?? entry["en"] ?? key.rawValue
        case .spanish: return entry["es"] ?? entry["en"] ?? key.rawValue
        case .french: return entry["fr"] ?? entry["en"] ?? key.rawValue
        case .german: return entry["de"] ?? entry["en"] ?? key.rawValue
        case .chineseSimplified: return entry["zh"] ?? entry["en"] ?? key.rawValue
        case .japanese: return entry["ja"] ?? entry["en"] ?? key.rawValue
        case .korean: return entry["ko"] ?? entry["en"] ?? key.rawValue
        case .portuguese: return entry["pt"] ?? entry["en"] ?? key.rawValue
        case .arabic: return entry["ar"] ?? entry["en"] ?? key.rawValue
        }
    }

    static func settingsTabName(_ tab: SettingsTab, language: AppLanguage) -> String {
        switch tab {
        case .general: return string(.settingsTabGeneral, language: language)
        case .codePreview: return string(.settingsTabCodePreview, language: language)
        case .modelSettings: return string(.settingsTabModelSettings, language: language)
        case .providers: return string(.settingsTabProviders, language: language)
        case .skills: return string(.settingsTabSkills, language: language)
        case .mcpServers: return string(.settingsTabMCPServers, language: language)
        case .lspServers:
            switch language {
            case .russian: return "Языковые серверы"
            case .spanish: return "Servidores de lenguaje"
            case .french: return "Serveurs de langage"
            case .german: return "Sprachserver"
            default: return "LSP Servers"
            }
        case .plugins: return string(.settingsTabPlugins, language: language)
        case .commands: return string(.settingsTabCommands, language: language)
        case .indexing: return string(.settingsTabIndexing, language: language)
        case .storage:
            switch language {
            case .russian: return "Хранилище"
            case .spanish: return "Almacenamiento"
            case .french: return "Stockage"
            case .german: return "Speicher"
            case .chineseSimplified: return "存储"
            case .japanese: return "ストレージ"
            case .korean: return "저장소"
            case .portuguese: return "Armazenamento"
            case .arabic: return "التخزين"
            case .english: return "Storage"
            }
        case .usage: return string(.settingsTabUsage, language: language)
        }
    }

    static let translations: [String: [String: String]] = makeTranslations()

    /// Builds the merged translation table. Swift 6.3's `COWArrayOptPass`
    /// spent hours on this single ~1,000-entry nested dictionary under `-O`,
    /// so the literal lives in explicitly unoptimized part functions and the
    /// optimizer skips them; initialization still runs exactly once.
    @_optimize(none)
    private static func makeTranslations() -> [String: [String: String]] {
        var merged: [String: [String: String]] = [:]
        for part in [translationsPart1(), translationsPart2()] {
            for (key, value) in part { merged[key] = value }
        }
        return merged
    }
}
