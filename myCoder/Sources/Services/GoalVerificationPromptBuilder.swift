import Foundation

/// Builds the prompts for automatic goal verification (ЦЕЛЬ):
/// - a *devil's-advocate* internal-model prompt that checks whether the plan
///   steps are really done, and names exactly what is not;
/// - the continuation prompt («продолжай по плану, обнови прогресс») that is
///   injected when the plan is not complete yet;
/// - the language decision so all prompts follow the selected app language.
enum GoalVerificationPromptBuilder {

    static var `default` = AppLanguage.english

    /// Language of the prompts. Falls back to English for languages that do
    /// not yet have a translation.
    private static func lang(_ language: AppLanguage) -> AppLanguage {
        switch language {
        case .russian: return .russian
        case .english: return .english
        default: return .english
        }
    }

    /// System instruction for the internal model acting as devil's advocate.
    static func devilAdvocateSystem(language: AppLanguage) -> String {
        switch lang(language) {
        case .russian:
            return """
            Ты — строгий адвокат дьявола. Твоя задача — проверить, действительно ли \
            выполнен план поставленной цели, а не верить формулировкам. \
            Действуй по шагам:
            1) Сравни каждый пункт плана с последним ответом модели и реальным состоянием работы.
            2) Если пункт сделан — пометь его как done. Если нет — укажи, что именно не готово.
            3) Если модель просто обещает («сделаю», «планирую») — это НЕ выполнение.
            4) Верни только JSON: {"complete": true|false, "notDone": ["пункт", ...], "reason": "..."}
            5) Если не готово, reason обязан перечислить конкретно, что не готово.
            """
        default:
            return """
            You are a strict devil's advocate. Your job is to check whether the plan \
            for the given goal is REALLY done — do not trust the wording. \
            Steps:
            1) Compare each plan step with the model's last answer and the actual state of work.
            2) If a step is done, mark it done. If not, state exactly what is not done.
            3) If the model only promises ("I will", "planning") — that is NOT completion.
            4) Reply with JSON only: {"complete": true|false, "notDone": ["item", ...], "reason": "..."}
            5) When not complete, reason must enumerate concretely what is not done.
            """
        }
    }

    /// User content for the verification call: the goal, the plan, and the
    /// model's last answer to check.
    static func verificationUser(goal: UserGoal, lastAssistantText: String, language: AppLanguage) -> String {
        let planLines = goal.plan.enumerated().map { i, item in
            "- [\(item.status.rawValue)] \(item.title)\(item.note.map { " — \($0)" } ?? "")"
        }.joined(separator: "\n")
        switch lang(language) {
        case .russian:
            return """
            Цель: \(goal.title)

            План:
            \(planLines)

            Последний ответ модели:
            \(lastAssistantText.isEmpty ? "(пусто)" : lastAssistantText)
            """
        default:
            return """
            Goal: \(goal.title)

            Plan:
            \(planLines)

            Model's last answer:
            \(lastAssistantText.isEmpty ? "(empty)" : lastAssistantText)
            """
        }
    }

    /// The auto-continue prompt injected when the plan is not complete yet.
    static func continuationMessage(language: AppLanguage, reason: String = "") -> String {
        let reasonPart = reason.isEmpty ? "" : " \(reason)"
        switch lang(language) {
        case .russian:
            return "Продолжай по плану, обнови прогресс. План ещё не полностью готов:\(reasonPart)"
        default:
            return "Continue per the plan and update progress. The plan is not fully complete yet:\(reasonPart)"
        }
    }

    /// Prompt used right after a goal starts, when the plan is not ready yet.
    static func readinessMessage(language: AppLanguage) -> String {
        switch lang(language) {
        case .russian:
            return "Продолжай по плану, обнови прогресс. Сначала составь план по цели через todo_ инструменты."
        default:
            return "Continue per the plan and update progress. First build the plan for the goal using todo_ tools."
        }
    }
}
