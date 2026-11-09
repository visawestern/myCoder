import Foundation

/// Общие низкоуровневые хелперы разбора параметров действий: типизированные
/// чтения из `[String: Any]` и нормализация значений. Вынесены из основного
/// файла (лимит ≤600 строк).
@MainActor
extension AppActionRouter {
    // MARK: - Parameter helpers

    static func language(named raw: String) -> AppLanguage? {
        if let direct = AppLanguage(rawValue: raw) { return direct }
        switch raw.lowercased() {
        case "en", "english": return .english
        case "ru", "russian": return .russian
        case "es", "spanish": return .spanish
        case "fr", "french": return .french
        case "de", "german": return .german
        case "zh", "chinese": return .chineseSimplified
        case "ja", "japanese": return .japanese
        case "ko", "korean": return .korean
        case "pt", "portuguese": return .portuguese
        case "ar", "arabic": return .arabic
        default: return nil
        }
    }

    func stateName(_ state: SpecWizardChecklistLogic.ItemState) -> String {
        switch state {
        case .done: return "done"
        case .pending: return "pending"
        case .upcoming: return "upcoming"
        }
    }

    func jsonValue(_ raw: String?) -> Any? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func requireString(_ name: String, _ params: [String: Any]) throws -> String {
        guard let raw = params[name] as? String, !raw.isEmpty else {
            throw AppActionError.missingParameter(name)
        }
        return raw
    }

    func requireBool(_ name: String, _ params: [String: Any]) throws -> Bool {
        guard let value = bool(params[name]) else {
            throw AppActionError.missingParameter(name)
        }
        return value
    }

    func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}
