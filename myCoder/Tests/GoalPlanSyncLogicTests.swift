import Testing
import Foundation
@testable import myCoder

/// Жалоба владельца 2026-11-13: у активной цели «ремонтируй аквариум…»
/// панель плана показывает «Нет шагов» и после перезапуска приложения, хотя
/// модель уже построила чеклист через todo-инструменты.
///
/// Причина: `goal.plan` никто не заполнял — чеклист жил только в
/// `todos.json` и в памяти панели. Здесь чистое преобразование сохранённых
/// todo-элементов в шаги плана цели; запись в GoalStore делает сервис.
@MainActor
@Suite("Синхронизация плана цели с todo-чеклистом")
struct GoalPlanSyncLogicTests {

    @Test("Todo-элементы становятся шагами плана в исходном порядке")
    func mapsItemsInOrder() {
        let items: [[String: Any]] = [
            ["content": "Открыть аквариум в браузере", "status": "completed"],
            ["content": "Починить WebGL-контекст", "status": "in_progress"],
            ["content": "Проверить анимацию воды", "status": "pending"],
        ]
        let plan = GoalPlanSyncLogic.planItems(fromTodoItems: items)

        #expect(plan.map(\.title) == [
            "Открыть аквариум в браузере",
            "Починить WebGL-контекст",
            "Проверить анимацию воды",
        ])
        #expect(plan.map(\.status) == [.done, .inProgress, .todo])
        #expect(plan.allSatisfy { $0.note == nil })
    }

    @Test("Статусы todo переводятся в статусы плана")
    func mapsStatuses() {
        let cases: [(String, UserGoal.PlanItem.Status)] = [
            ("pending", .todo),
            ("in_progress", .inProgress),
            ("in-progress", .inProgress),
            ("completed", .done),
            ("done", .done),
            ("cancelled", .blocked),
            ("failed", .blocked),
            ("blocked", .blocked),
            ("unknown", .todo),
        ]
        for (raw, expected) in cases {
            let plan = GoalPlanSyncLogic.planItems(
                fromTodoItems: [["content": "шаг", "status": raw]]
            )
            #expect(plan.first?.status == expected, "статус \(raw) → \(expected)")
        }
    }

    @Test("Пустые и повреждённые элементы пропускаются, а не превращаются в пустые шаги")
    func skipsEmptyItems() {
        let items: [[String: Any]] = [
            ["content": "  ", "status": "pending"],
            ["status": "pending"],
            ["content": "реальный шаг", "status": "pending"],
        ]
        let plan = GoalPlanSyncLogic.planItems(fromTodoItems: items)
        #expect(plan.map(\.title) == ["реальный шаг"])
    }

    @Test("Нет todo-элементов — нет шагов плана")
    func emptyInputYieldsEmptyPlan() {
        #expect(GoalPlanSyncLogic.planItems(fromTodoItems: []).isEmpty)
    }

    @Test("План из todo-элементов не теряет уже отмеченные done шаги")
    func keepsCompletedSteps() {
        let plan = GoalPlanSyncLogic.planItems(fromTodoItems: [
            ["content": "шаг 1", "status": "completed"],
            ["content": "шаг 2", "status": "completed"],
        ])
        #expect(plan.count == 2)
        #expect(GoalPlanStatusLogic.isComplete(plan))
    }
}
