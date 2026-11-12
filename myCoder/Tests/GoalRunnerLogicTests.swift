import Testing
import Foundation
@testable import myCoder

/// «Старт» цели должен запускать автономный цикл: отправить промпт цели в
/// чат как юзер (с полным контекстом), контролировать, помечать прогресс и
/// продолжать, пока цель не выполнена (директива 2026-11-09).
@MainActor
@Suite("ЦЕЛЬ — запуск и авто-цикл")
struct GoalRunnerLogicTests {

    private func goal(plan: [UserGoal.PlanItem]) -> UserGoal {
        UserGoal(title: "Цель", plan: plan)
    }

    private func item(_ title: String, _ status: UserGoal.PlanItem.Status) -> UserGoal.PlanItem {
        UserGoal.PlanItem(title: title, status: status)
    }

    // MARK: - Первое сообщение

    @Test("Промпт старта — полный промпт цели (цель+план+продолжение+проверка)")
    func launchMessageIsFullPrompt() {
        let g = goal(plan: [item("Шаг 1", .todo)])
        let message = GoalRunner.launchMessage(goal: g, language: .russian)
        #expect(message.contains(g.title))
        #expect(message.contains("Шаг 1"))
        #expect(message.contains("Продолжай по плану") || message.contains("summary"))  // полнота
        #expect(message.utf8.count > 200)
    }

    // MARK: - Обновление плана по вердикту

    @Test("Вердикт complete → все шаги done")
    func completeVerdictMarksAllDone() {
        let plan = [item("Шаг 1", .todo), item("Шаг 2", .inProgress)]
        let updated = GoalRunner.updatedPlan(plan, verdict: GoalVerdict(complete: true, notDone: [], reason: "", valid: true))
        #expect(updated.allSatisfy { $0.status == .done })
    }

    @Test("Неполный вердикт → подтверждённые шаги done, остальные in_progress")
    func incompleteVerdictMarksProgress() {
        let plan = [item("Шаг 1", .todo), item("Шаг 2", .todo), item("Шаг 3", .done)]
        let verdict = GoalVerdict(complete: false, notDone: ["Шаг 2"], reason: "Шаг 2 не готов", valid: true)
        let updated = GoalRunner.updatedPlan(plan, verdict: verdict)
        let byTitle = Dictionary(uniqueKeysWithValues: updated.map { ($0.title, $0.status) })
        #expect(byTitle["Шаг 1"] == .done)      // не в notDone → подтверждён
        #expect(byTitle["Шаг 2"] == .inProgress) // текущая работа
        #expect(byTitle["Шаг 3"] == .done)
    }

    @Test("Пустой notDone при неполном вердикте → ничего не портит")
    func emptyNotDoneDoesNotBreakPlan() {
        let plan = [item("Шаг 1", .todo)]
        let updated = GoalRunner.updatedPlan(plan, verdict: GoalVerdict(complete: false, notDone: [], reason: "", valid: true))
        #expect(updated.count == 1)
        #expect(updated[0].status == .done) // пустой notDone → считаем всё выполненным
    }

    @Test("Сложные статусы: blocked не трогается, если в notDone")
    func blockedStaysBlockedWhenInNotDone() {
        let plan = [item("Шаг 1", .blocked)]
        let updated = GoalRunner.updatedPlan(plan, verdict: GoalVerdict(complete: false, notDone: ["Шаг 1"], reason: "", valid: true))
        #expect(updated[0].status == .blocked)
    }

    @Test("blocked вне notDone остаётся blocked, а не становится done")
    func blockedNotInNotDoneStaysBlocked() {
        // Контракт updatedPlan: blocked — это не «готово»; модель могла
        // забыть перечислить шаг в notDone, и он не должен молча закрыться.
        let plan = [item("Шаг 1", .blocked), item("Шаг 2", .todo)]
        let updated = GoalRunner.updatedPlan(plan, verdict: GoalVerdict(complete: false, notDone: ["Шаг 2"], reason: "Шаг 2 не готов", valid: true))
        let byTitle = Dictionary(uniqueKeysWithValues: updated.map { ($0.title, $0.status) })
        #expect(byTitle["Шаг 1"] == .blocked)
        #expect(byTitle["Шаг 2"] == .inProgress)
    }

    // MARK: - Продолжение цикла

    @Test("continue неполном вердикте цикл продолжается, при complete — завершается")
    func shouldContinueFollowsVerdict() {
        #expect(GoalRunner.shouldContinue(after: GoalVerdict(complete: false, notDone: ["x"], reason: "", valid: true)))
        #expect(!GoalRunner.shouldContinue(after: GoalVerdict(complete: true, notDone: [], reason: "", valid: true)))
    }

    @Test("Запуск цели сразу помечает её активной")
    func launchMarksGoalActive() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let goal = UserGoal(title: "Запустить", chatID: "chat-a")
        try GoalStore.upsert(goal, homeDirectory: home)
        let launched = GoalLauncher.launch(
            goalID: goal.id,
            homeDirectory: home,
            language: .russian,
            fallbackChatID: "chat-a"
        )
        #expect(launched)
        #expect(GoalStore.load(homeDirectory: home).first?.state == .active)
    }
}
