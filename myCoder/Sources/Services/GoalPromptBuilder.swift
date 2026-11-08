import Foundation

/// Builds the FULL prompt of a goal — what the goal actually asks for:
/// the goal itself, its plan, the continuation instruction and the
/// devil's-advocate verification prompt.
///
/// The text is deterministic: the same goal always produces the same prompt,
/// so the panel and the sidebar show exactly what the model was told.
enum GoalPromptBuilder {

    static func fullPrompt(goal: UserGoal, language: AppLanguage) -> String {
        let russian = language == .russian
        let planLines = goal.plan.enumerated().map { index, item in
            let note = item.note.map { " — \($0)" } ?? ""
            return "\(index + 1). [\(item.status.rawValue)] \(item.title)\(note)"
        }.joined(separator: "\n")

        let goalLabel = russian ? "Цель" : "Goal"
        let planLabel = russian ? "План" : "Plan"
        let emptyPlan = russian ? "(план пуст)" : "(the plan is empty)"
        let continuationLabel = russian ? "Продолжение" : "Continuation"
        let verificationLabel = russian ? "Проверка (адвокат дьявола)" : "Verification (devil's advocate)"

        return """
        \(goalLabel): \(goal.title)

        \(planLabel):
        \(planLines.isEmpty ? emptyPlan : planLines)

        \(continuationLabel):
        \(GoalVerificationPromptBuilder.continuationMessage(language: language))

        \(verificationLabel):
        \(GoalVerificationPromptBuilder.devilAdvocateSystem(language: language))

        \(GoalVerificationPromptBuilder.verificationUser(goal: goal, lastAssistantText: "", language: language))
        """
    }
}

/// The prompt as the UI needs it: the text plus the rule that decides whether
/// it has to scroll.
///
/// A prompt longer than ten wrapped lines must not push the panel or the
/// composer away — it scrolls inside its own frame instead.
struct GoalPromptPresentation: Equatable, Sendable {
    /// How many lines are shown before the prompt starts scrolling.
    static let visibleLineLimit = 10

    let text: String

    /// Number of lines in the prompt, counting explicit line breaks.
    var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// True when the prompt is taller than the visible window.
    var exceedsVisibleLines: Bool {
        lineCount > Self.visibleLineLimit
    }
}
