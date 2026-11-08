import Foundation

/// Политика авто-продолжения цикла цели (директива 2026-11-09):
/// жёсткий общий лимит итераций НЕ применяется, пока план движется
/// (появляются done-шаги). Лимит действует только на безрезультатные
/// попытки — когда после продолжения план не изменился (модель буксует,
/// ошибки, пустые ответы).
enum GoalCyclePolicy {

    /// Сколько БЕЗРЕЗУЛЬТАТНЫХ продолжений подряд допустимо, прежде чем
    /// цикл остановится (защита от зацикливания на ошибках).
    static let maxConsecutiveFailures = 3

    /// Прогресс есть, если выполненных шагов стало больше.
    static func progressed(from before: [UserGoal.PlanItem], to after: [UserGoal.PlanItem]) -> Bool {
        let doneBefore = before.filter { $0.status == .done }.count
        let doneAfter = after.filter { $0.status == .done }.count
        return doneAfter > doneBefore
    }

    /// Остановиться после `failureCount` безрезультатных попыток подряд.
    static func shouldStopAfterNoProgress(failureCount: Int) -> Bool {
        failureCount >= maxConsecutiveFailures
    }

    /// Успешная итерация (есть прогресс) сбрасывает счётчик.
    static func success(afterFailureCount count: Int) -> Int {
        0
    }

    /// Безрезультатная итерация увеличивает счётчик.
    static func failure(afterFailureCount count: Int) -> Int {
        count + 1
    }

    /// С какой пометкой цель остаётся после исчерпания лимита безрезультатных
    /// попыток: честно — поставлена на паузу с причиной, а не «висит» в
    /// active, будто продолжается.
    static let stallReason =
        "Превышен лимит безрезультатных проверок. Подтвердите выполнение или продолжите вручную."
}

/// Источник «звоночка»: когда чат ждёт решения пользователя — одобрение
/// инструмента или ответ на вопрос. Используется сайдбаром для моргающей
/// подсветки чата (а если проект скрыт — самого проекта).
enum SidebarAttentionLogic {

    static func chatNeedsAttention(sessionID: String,
                                   pendingApprovalCount: Int,
                                   pendingQuestionSessionID: String?) -> Bool {
        if pendingApprovalCount > 0 {
            return true
        }
        if let pendingQuestionSessionID, !pendingQuestionSessionID.isEmpty {
            return pendingQuestionSessionID == sessionID
        }
        return false
    }

    static func projectNeedsAttention(hasAttention: Bool) -> Bool {
        hasAttention
    }
}
