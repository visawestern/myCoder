import Foundation

enum ProviderNameLogic {
    static func resolvedName(_ raw: String, fallback: String, existing: [String]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }
}
