import Testing
import Foundation
@testable import myCoder

/// Авто-цикл цели должен продолжаться без жёсткого общего лимита, пока план
/// движется; maxAutoContinues применяется ТОЛЬКО к безрезультатным попыткам
/// (ошибки/застревание) — директива 2026-11-09.
@Suite("ЦЕЛЬ — политика авто-продолжения")
struct GoalCyclePolicyTests {

    private func item(_ title: String, _ status: UserGoal.PlanItem.Status) -> UserGoal.PlanItem {
        UserGoal.PlanItem(title: title, status: status)
    }

    @Test("Прогресс есть, когда done стало больше")
    func progressedDetectsNewDoneSteps() {
        let before = [item("Шаг 1", .todo), item("Шаг 2", .todo)]
        let after = [item("Шаг 1", .done), item("Шаг 2", .inProgress)]
        #expect(GoalCyclePolicy.progressed(from: before, to: after))
    }

    @Test("Прогресса нет, когда done не прибавилось")
    func noProgressWhenDoneUnchanged() {
        let before = [item("Шаг 1", .inProgress), item("Шаг 2", .todo)]
        let after = [item("Шаг 1", .inProgress), item("Шаг 2", .inProgress)]
        #expect(!GoalCyclePolicy.progressed(from: before, to: after))
    }

    @Test("Пустой план → прогресса нет")
    func emptyPlanHasNoProgress() {
        #expect(!GoalCyclePolicy.progressed(from: [], to: []))
    }

    @Test("Лимит безрезультатных попыток: стоп после N подряд")
    func stopsAfterConsecutiveFailures() {
        let max = GoalCyclePolicy.maxConsecutiveFailures
        #expect(max > 0)
        #expect(!GoalCyclePolicy.shouldStopAfterNoProgress(failureCount: max - 1))
        #expect(GoalCyclePolicy.shouldStopAfterNoProgress(failureCount: max))
        #expect(GoalCyclePolicy.shouldStopAfterNoProgress(failureCount: max + 1))
    }

    @Test("Успех сбрасывает счётчик безрезультатных попыток")
    func successResetsFailureCount() {
        #expect(GoalCyclePolicy.success(afterFailureCount: 2) == 0)
        #expect(GoalCyclePolicy.failure(afterFailureCount: 0) == 1)
        #expect(GoalCyclePolicy.failure(afterFailureCount: 3) == 4)
    }

    @Test("Причина стагнации существует и читаема")
    func stallReasonIsPresent() {
        #expect(!GoalCyclePolicy.stallReason.isEmpty)
    }
}

/// «Звоночек» в списке чатов: чат ждёт решения пользователя (одобрение
/// инструмента или вопрос). Если проект скрыт — мигает сам проект.
@Suite("Сайдбар — звоночек внимания")
struct SidebarAttentionLogicTests {

    @Test("Чат требует внимания при ожидающем одобрении")
    func approvalMarksChatAttention() {
        #expect(SidebarAttentionLogic.chatNeedsAttention(
            sessionID: "s1", pendingApprovalCount: 1, pendingQuestionSessionID: nil))
        #expect(!SidebarAttentionLogic.chatNeedsAttention(
            sessionID: "s1", pendingApprovalCount: 0, pendingQuestionSessionID: nil))
    }

    @Test("Чат требует внимания, когда ему задан вопрос")
    func pendingQuestionMarksChatAttention() {
        #expect(SidebarAttentionLogic.chatNeedsAttention(
            sessionID: "s1", pendingApprovalCount: 0, pendingQuestionSessionID: "s1"))
        #expect(!SidebarAttentionLogic.chatNeedsAttention(
            sessionID: "s1", pendingApprovalCount: 0, pendingQuestionSessionID: "s2"))
    }

    @Test("Проект требует внимания, если хотя бы один его чат ждёт решения")
    func projectAttentionFollowsChildren() {
        #expect(SidebarAttentionLogic.projectNeedsAttention(hasAttention: true))
        #expect(!SidebarAttentionLogic.projectNeedsAttention(hasAttention: false))
    }
}
