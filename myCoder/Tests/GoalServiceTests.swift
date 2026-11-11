import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("ЦЕЛЬ — GoalService")
struct GoalServiceTests {

    private func home() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("Создание и список")
    func createAndList() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let created = try GoalService.apply(.create(title: "Сделать фичу"), homeDirectory: h, language: .russian)
        #expect(created.goals.count == 1)
        #expect(created.goals.first?.title == "Сделать фичу")
        #expect(created.goals.first?.state == .pending)
        let list = try GoalService.apply(.list, homeDirectory: h, language: .russian)
        #expect(list.reply.contains("Сделать фичу"))
    }

    @Test("Start без плана возвращает промпт готовности")
    func startWithoutPlan() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        try GoalService.apply(.create(title: "Цель"), homeDirectory: h, language: .russian)
        let started = try GoalService.apply(.start, homeDirectory: h, language: .russian)
        #expect(started.goals.first?.state == .active)
        #expect(started.reply.contains("Продолжай по плану"))
    }

    @Test("Пауза и возобновление")
    func pauseResume() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        try GoalService.apply(.create(title: "Цель"), homeDirectory: h, language: .russian)
        _ = try GoalService.apply(.start, homeDirectory: h, language: .russian)
        let paused = try GoalService.apply(.pause, homeDirectory: h, language: .russian)
        #expect(paused.goals.first?.state == .paused)
        let resumed = try GoalService.apply(.resume, homeDirectory: h, language: .russian)
        #expect(resumed.goals.first?.state == .active)
    }

    @Test("Удаление")
    func delete() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        try GoalService.apply(.create(title: "Цель"), homeDirectory: h, language: .russian)
        let deleted = try GoalService.apply(.delete(index: nil), homeDirectory: h, language: .russian)
        #expect(deleted.goals.isEmpty)
    }
}

@MainActor
@Suite("ЦЕЛЬ — авто-проверка адвокатом дьявола")
struct GoalVerificationServiceTests {

    @Test("Невыполненный план → промпт-продолжение")
    func incompleteReturnsContinuation() async {
        let goal = UserGoal(title: "Цель", plan: [
            .init(title: "Шаг 1", status: .done),
            .init(title: "Шаг 2", status: .todo)
        ])
        let service = GoalVerificationService { _, _ in
            #"{"complete": false, "notDone": ["Шаг 2"], "reason": "Шаг 2 не готов"}"#
        }
        let outcome = await service.verify(goal: goal, lastAssistantText: "текст", language: .russian)
        #expect(outcome.verdict.complete == false)
        #expect(outcome.verdict.notDone == ["Шаг 2"])
        #expect(outcome.continuation?.contains("Продолжай по плану") == true)
    }

    @Test("Выполненный план → без продолжения")
    func completeNoContinuation() async {
        let goal = UserGoal(title: "Цель", plan: [
            .init(title: "Шаг 1", status: .done),
            .init(title: "Шаг 2", status: .done)
        ])
        let service = GoalVerificationService { _, _ in
            #"{"complete": true, "notDone": [], "reason": ""}"#
        }
        let outcome = await service.verify(goal: goal, lastAssistantText: "готово", language: .english)
        #expect(outcome.verdict.complete == true)
        #expect(outcome.continuation == nil)
    }

    @Test("Модель вернула не-JSON → план решает сам")
    func fallbackToPlanWhenModelBroken() async {
        let goal = UserGoal(title: "Цель", plan: [
            .init(title: "Шаг 1", status: .todo)
        ])
        let service = GoalVerificationService { _, _ in "не json" }
        let outcome = await service.verify(goal: goal, lastAssistantText: "x", language: .russian)
        #expect(outcome.verdict.complete == false)
        #expect(outcome.verdict.notDone == ["Шаг 1"])
        #expect(outcome.continuation != nil)
    }

    /// Живой дефект 2026-11-09: цель без плана (модель работала напрямую и
    /// не вела todo_шаги) никогда не закрывалась — host принудительно считал
    /// пустой план неполным, авто-цикл крутился и останавливался, а цель
    /// оставалась active. Когда плана нет, валидному вердикту модели
    /// доверяем: complete=true → цель выполнена.
    @Test("Пустой план + модель подтвердила complete → цель выполнена")
    func emptyPlanTrustsModelVerdict() async {
        let goal = UserGoal(title: "Цель", plan: [])
        let service = GoalVerificationService { _, _ in
            #"{"complete": true, "notDone": [], "reason": "готово"}"#
        }
        let outcome = await service.verify(goal: goal, lastAssistantText: "готово", language: .russian)
        #expect(outcome.verdict.complete == true)
        #expect(outcome.continuation == nil)
    }

    @Test("Пустой план + модель без валидного вердикта → продолжение")
    func emptyPlanWithoutModelVerdictContinues() async {
        let goal = UserGoal(title: "Цель", plan: [])
        let service = GoalVerificationService { _, _ in "не json" }
        let outcome = await service.verify(goal: goal, lastAssistantText: "x", language: .russian)
        #expect(outcome.verdict.complete == false)
        #expect(outcome.continuation != nil)
    }

    @Test("План есть: модель говорит complete, но шаги не done → не верю")
    func nonEmptyPlanStillDeterministic() async {
        let goal = UserGoal(title: "Цель", plan: [
            .init(title: "Шаг 1", status: .todo)
        ])
        let service = GoalVerificationService { _, _ in
            #"{"complete": true, "notDone": [], "reason": "сделано"}"#
        }
        let outcome = await service.verify(goal: goal, lastAssistantText: "готово", language: .russian)
        #expect(outcome.verdict.complete == false)
        #expect(outcome.verdict.notDone == ["Шаг 1"])
        #expect(outcome.continuation != nil)
    }
}
