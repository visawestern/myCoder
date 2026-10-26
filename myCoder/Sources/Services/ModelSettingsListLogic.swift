import Foundation

/// Pure list rules for the compact provider-detail model list: flat order
/// (no prefix grouping) and a hard ten-row cap so the card never grows
/// without bound.
enum ModelSettingsListLogic {
    static let limit = 10

    static func visibleModels(_ models: [String], query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? models
            : models.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        return Array(filtered.prefix(limit))
    }
}
