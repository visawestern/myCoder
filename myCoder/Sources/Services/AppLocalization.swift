import Foundation

enum AppLocalization {
    static func string(forEnglish english: String, language: AppLanguage) -> String {
        let matches = translations.filter { $0.value["en"] == english }
        // Several keys can share the same English label. Prefer a real
        // AppLocalizationKey (the canonical translation) and break ties by
        // key name so the result never depends on dictionary order.
        guard let entry = matches
            .min(by: { rank($0.key) < rank($1.key) })?
            .value else {
            return english
        }
        return value(in: entry, language: language) ?? entry["en"] ?? english
    }

    private static func rank(_ key: String) -> (Int, String) {
        (AppLocalizationKey(rawValue: key) == nil ? 1 : 0, key)
    }

    private static func value(in entry: [String: String], language: AppLanguage) -> String? {
        switch language {
        case .english: return entry["en"]
        case .russian: return entry["ru"] ?? entry["en"]
        case .spanish: return entry["es"] ?? entry["en"]
        case .french: return entry["fr"] ?? entry["en"]
        case .german: return entry["de"] ?? entry["en"]
        case .chineseSimplified: return entry["zh"] ?? entry["en"]
        case .japanese: return entry["ja"] ?? entry["en"]
        case .korean: return entry["ko"] ?? entry["en"]
        case .portuguese: return entry["pt"] ?? entry["en"]
        case .arabic: return entry["ar"] ?? entry["en"]
        }
    }

    static func string(_ key: AppLocalizationKey, language: AppLanguage) -> String {
        guard let entry = translations[key.rawValue] else { return key.rawValue }
        return value(in: entry, language: language) ?? key.rawValue
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
        for part in [translationsPart1(), translationsPart2(), translationsPart3()] {
            for (key, value) in part { merged[key] = value }
        }
        return merged
    }
}
