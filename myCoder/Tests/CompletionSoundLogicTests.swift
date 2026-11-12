import Foundation
import Testing
@testable import myCoder

/// Гейт звука завершения хода: звук играет только когда чат реально
/// закончил работу, нет активной цели, ошибки, остановки или ожидания
/// действия пользователя (запрос 2026-11-13).
@MainActor
@Suite("Логика звука завершения хода")
struct CompletionSoundLogicTests {

    @Test("Завершённый ход без препятствий играет звук")
    func playsWhenCompleted() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: true,
            activeGoalRunning: false,
            endedWithError: false,
            stoppedByUser: false,
            awaitingUserInput: false
        )) == .play)
    }

    @Test("Активная цель отключает звук")
    func skipsWhenGoalRunning() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: true,
            activeGoalRunning: true,
            endedWithError: false,
            stoppedByUser: false,
            awaitingUserInput: false
        )) == .skip)
    }

    @Test("Ошибка отключает звук")
    func skipsOnError() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: true,
            activeGoalRunning: false,
            endedWithError: true,
            stoppedByUser: false,
            awaitingUserInput: false
        )) == .skip)
    }

    @Test("Остановка пользователем отключает звук")
    func skipsOnStop() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: true,
            activeGoalRunning: false,
            endedWithError: false,
            stoppedByUser: true,
            awaitingUserInput: false
        )) == .skip)
    }

    @Test("Ожидание действия пользователя отключает звук")
    func skipsOnPendingQuestion() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: true,
            activeGoalRunning: false,
            endedWithError: false,
            stoppedByUser: false,
            awaitingUserInput: true
        )) == .skip)
    }

    @Test("Незавершённый ход не играет звук")
    func skipsWhenNotCompleted() {
        #expect(CompletionSoundLogic.decide(CompletionTurnContext(
            completed: false,
            activeGoalRunning: false,
            endedWithError: false,
            stoppedByUser: false,
            awaitingUserInput: false
        )) == .skip)
    }

    @Test("hasActiveGoal видит активную цель из хранилища")
    func hasActiveGoal() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-sound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(CompletionSoundLogic.hasActiveGoal(homeDirectory: home) == false)

        let goal = UserGoal(title: "тест", state: .active)
        try GoalStore.save([goal], homeDirectory: home)
        #expect(CompletionSoundLogic.hasActiveGoal(homeDirectory: home) == true)

        let paused = UserGoal(title: "пауза", state: .paused)
        try GoalStore.save([paused], homeDirectory: home)
        #expect(CompletionSoundLogic.hasActiveGoal(homeDirectory: home) == false)
    }
}
