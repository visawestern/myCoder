import Foundation

enum ProviderConnectionValidationLogic {
    static func modelIDs(from body: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return []
        }

        var ids: [String] = []
        for value in (json["data"] as? [[String: Any]]) ?? [] {
            if let id = nonEmpty(value["id"] as? String) {
                ids.append(id)
            }
        }

        for value in (json["models"] as? [[String: Any]]) ?? [] {
            let id = nonEmpty(value["id"] as? String)
            let name = nonEmpty(value["name"] as? String)
            guard let raw = id ?? name else { continue }
            let normalized = raw.hasPrefix("models/")
                ? String(raw.dropFirst("models/".count))
                : raw
            if let model = nonEmpty(normalized) {
                ids.append(model)
            }
        }

        return Array(Set(ids)).sorted()
    }

    static func isValidModelsResponse(statusCode: Int, body: Data) -> Bool {
        guard (200..<300).contains(statusCode) else { return false }
        return !modelIDs(from: body).isEmpty
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
