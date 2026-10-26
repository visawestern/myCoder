import Foundation

enum SessionGoalPersistenceLogic {
    static func normalizedGoal(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func effectiveGoal(projectStoredGoal: String?, legacyStoredGoal: String?) -> String? {
        if let project = projectStoredGoal.flatMap(normalizedGoal) {
            return project
        }
        return legacyStoredGoal.flatMap(normalizedGoal)
    }
}
