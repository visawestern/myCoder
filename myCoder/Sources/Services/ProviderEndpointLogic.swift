import Foundation

enum ProviderEndpointLogic {
    static func normalizedBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard URL(string: normalized) != nil else { return nil }
        return normalized
    }

    static func modelsURL(for raw: String) -> String? {
        guard let base = normalizedBaseURL(raw),
              let url = URL(string: base) else { return nil }
        return url.appendingPathComponent("models").absoluteString
    }

    static func defaultRequiresAPIKey(for type: ProviderType) -> Bool {
        switch type {
        case .ollama, .acp, .openCodeZen:
            return false
        default:
            return true
        }
    }
}
