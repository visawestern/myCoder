import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("ЦЕЛЬ — модель и хранилище")
struct GoalStoreTests {

    private func makeGoal(title: String = "Рефакторинг") -> UserGoal {
        UserGoal(title: title, plan: [
            .init(title: "Разбить модуль", status: .todo),
            .init(title: "Покрыть тестами", status: .done),
            .init(title: "Прогнать сборку", status: .todo)
        ])
    }

    @Test("Сохранение и загрузка сохраняют план и состояния")
    func roundTrip() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let goal = makeGoal()
        try GoalStore.upsert(goal, homeDirectory: home)
        let loaded = GoalStore.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == goal.id)
        #expect(loaded.first?.plan.count == 3)
        #expect(loaded.first?.plan[1].status == .done)
    }

    @Test("upsert обновляет существующую цель, а не дублирует")
    func upsertUpdates() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var goal = makeGoal()
        try GoalStore.upsert(goal, homeDirectory: home)
        goal.title = "Изменено"
        goal.plan[0].status = .done
        try GoalStore.upsert(goal, homeDirectory: home)
        let loaded = GoalStore.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "Изменено")
        #expect(loaded.first?.plan[0].status == .done)
    }

    @Test("remove и setState работают")
    func removeAndSetState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let goal = makeGoal()
        try GoalStore.upsert(goal, homeDirectory: home)
        try GoalStore.setState(id: goal.id, state: .active, homeDirectory: home)
        #expect(GoalStore.load(homeDirectory: home).first?.state == .active)
        try GoalStore.remove(id: goal.id, homeDirectory: home)
        #expect(GoalStore.load(homeDirectory: home).isEmpty)
    }
}

@MainActor
@Suite("ЦЕЛЬ — готовность и полнота плана")
struct GoalPlanStatusLogicTests {

    @Test("План готов, когда есть хотя бы один шаг")
    func readiness() {
        #expect(GoalPlanStatusLogic.ready([]) == false)
        #expect(GoalPlanStatusLogic.ready([.init(title: "a", status: .todo)]) == true)
    }

    @Test("Полнота требует все шаги done")
    func completeness() {
        let allDone = [UserGoal.PlanItem(title: "a", status: .done),
                       UserGoal.PlanItem(title: "b", status: .done)]
        #expect(GoalPlanStatusLogic.isComplete(allDone) == true)
        let oneOpen = allDone + [UserGoal.PlanItem(title: "c", status: .inProgress)]
        #expect(GoalPlanStatusLogic.isComplete(oneOpen) == false)
        #expect(GoalPlanStatusLogic.notDoneItems(oneOpen) == ["c"])
    }

    @Test("Пустой план не считается выполненным")
    func emptyPlanNotComplete() {
        #expect(GoalPlanStatusLogic.isComplete([]) == false)
    }

    @Test("Лимит авто-продолжений защищает от бесконечного цикла")
    func maxAutoContinuesIsBounded() {
        #expect(GoalPlanStatusLogic.maxAutoContinues > 0)
        #expect(GoalPlanStatusLogic.maxAutoContinues <= 10)
    }
}

@MainActor
@Suite("ЦЕЛЬ — промпты адвоката дьявола")
struct GoalVerificationPromptBuilderTests {

    private func goal() -> UserGoal {
        UserGoal(title: "Цель", plan: [
            .init(title: "Шаг 1", status: .done),
            .init(title: "Шаг 2", status: .todo)
        ])
    }

    @Test("Промпт-продолжение на русском и английском")
    func continuationMessages() {
        #expect(GoalVerificationPromptBuilder.continuationMessage(language: .russian).contains("Продолжай по плану, обнови прогресс"))
        #expect(GoalVerificationPromptBuilder.continuationMessage(language: .english).contains("Continue per the plan and update progress"))
        #expect(GoalVerificationPromptBuilder.readinessMessage(language: .russian).contains("Продолжай по плану"))
    }

    @Test("Системный промпт адвоката требует JSON и конкретики")
    func devilAdvocateSystem() {
        let sys = GoalVerificationPromptBuilder.devilAdvocateSystem(language: .english).lowercased()
        #expect(sys.contains("devil's advocate"))
        #expect(sys.contains("\"complete\""))
        #expect(sys.contains("\"notdone\""))
    }

    @Test("Пользовательский запрос содержит цель, план и последний ответ")
    func verificationUser() {
        let user = GoalVerificationPromptBuilder.verificationUser(
            goal: goal(), lastAssistantText: "готово", language: .russian)
        #expect(user.contains("Цель: Цель"))
        #expect(user.contains("Шаг 1"))
        #expect(user.contains("Шаг 2"))
        #expect(user.contains("готово"))
    }
}
