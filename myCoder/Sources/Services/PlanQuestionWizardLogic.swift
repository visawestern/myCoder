import Foundation

enum PlanQuestionWizardLogic {
    static func isQuestionAnswered(
        _ question: PlanQuestion,
        selections: [String: Set<String>],
        otherTexts: [String: String]
    ) -> Bool {
        let selected = selections[question.id] ?? []
        let other = otherTexts[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !selected.isEmpty || !other.isEmpty
    }

    static func canAdvance(
        step: Int,
        questions: [PlanQuestion],
        selections: [String: Set<String>],
        otherTexts: [String: String]
    ) -> Bool {
        guard questions.indices.contains(step) else { return false }
        return isQuestionAnswered(questions[step], selections: selections, otherTexts: otherTexts)
    }

    static func allAnswered(
        questions: [PlanQuestion],
        selections: [String: Set<String>],
        otherTexts: [String: String]
    ) -> Bool {
        questions.allSatisfy { isQuestionAnswered($0, selections: selections, otherTexts: otherTexts) }
    }

    static func isLastStep(step: Int, total: Int) -> Bool {
        guard total > 0 else { return true }
        return step >= total - 1
    }

    static func progressLabel(step: Int, total: Int) -> String {
        "\(step + 1) / \(max(total, 1))"
    }

    static func progressFraction(step: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return Double(step + 1) / Double(total)
    }

    static func previousStep(from step: Int) -> Int? {
        step > 0 ? step - 1 : nil
    }

    static func nextStep(from step: Int, total: Int) -> Int? {
        step < total - 1 ? step + 1 : nil
    }
}
