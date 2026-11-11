import Testing
import Foundation
@testable import myCoder

/// C1/C2 (жалоба владельца 2026-11-09): строка сборки контекста и цель/шаги
/// не были привязаны к чату. Пока чат A собирает контекст, чат B показывал
/// его строку и не мог отправить сообщение; шаги плана чата A появлялись в
/// бейдже чата B. Здесь проверяется выбор per-session состояния и проводка
/// через `AppState`.
@MainActor
@Suite("Статусы, привязанные к чату (C1/C2)")
struct ContextSessionStatusLogicTests {

    // MARK: - Чистая логика выбора

    @Test("Сборка контекста видна только своему чату")
    func compilingScopedToChat() {
        let compiling: Set<String> = ["A"]
        #expect(ContextSessionStatusLogic.isCompiling(compiling: compiling, selectedSessionID: "A"))
        #expect(!ContextSessionStatusLogic.isCompiling(compiling: compiling, selectedSessionID: "B"))
        #expect(!ContextSessionStatusLogic.isCompiling(compiling: compiling, selectedSessionID: nil))
    }

    @Test("Стадия сборки видна только своему чату")
    func stageScopedToChat() {
        let stages = ["A": "Индекс проекта"]
        #expect(
            ContextSessionStatusLogic.stage(stages: stages, selectedSessionID: "A")
                == "Индекс проекта"
        )
        #expect(ContextSessionStatusLogic.stage(stages: stages, selectedSessionID: "B") == "")
        #expect(ContextSessionStatusLogic.stage(stages: stages, selectedSessionID: nil) == "")
    }

    @Test("Журнал сборки виден только своему чату")
    func logScopedToChat() {
        let log = ContextAssemblyLogLogic.begin(message: "запрос A", projectRoot: "/tmp/a")
        let logs = ["A": log]
        #expect(ContextSessionStatusLogic.log(logs: logs, selectedSessionID: "A") == log)
        #expect(ContextSessionStatusLogic.log(logs: logs, selectedSessionID: "B") == .empty)
        #expect(ContextSessionStatusLogic.log(logs: logs, selectedSessionID: nil) == .empty)
    }

    @Test("Шаги плана видны только своему чату")
    func stepsScopedToChat() {
        let steps = ["A": [TaskStep(title: "A1", status: .completed)]]
        #expect(
            ContextSessionStatusLogic.steps(stepsBySession: steps, selectedSessionID: "A")
                .map(\.title) == ["A1"]
        )
        #expect(
            ContextSessionStatusLogic.steps(stepsBySession: steps, selectedSessionID: "B").isEmpty
        )
        #expect(
            ContextSessionStatusLogic.steps(stepsBySession: steps, selectedSessionID: nil).isEmpty
        )
    }

    // MARK: - Проводка через AppState

    @MainActor
    @Test("Сборка контекста в чате A не блокирует чат B")
    func compilationDoesNotBlockOtherChat() {
        let state = AppState()
        state.selectedSession = ChatSession(id: "A")
        state.beginContextCompilation(sessionID: "A")
        state.setContextStage("Индекс проекта", sessionID: "A")

        #expect(state.isCompilingContext)
        #expect(state.contextPreparationStage == "Индекс проекта")

        // Пользователь ушёл в другой чат — там своя, чистая строка статуса.
        state.selectedSession = ChatSession(id: "B")
        #expect(!state.isCompilingContext)
        #expect(state.contextPreparationStage.isEmpty)

        // Вернулся — видит сборку своего чата.
        state.selectedSession = ChatSession(id: "A")
        #expect(state.isCompilingContext)
        #expect(state.contextPreparationStage == "Индекс проекта")

        state.endContextCompilation(sessionID: "A")
        #expect(!state.isCompilingContext)
    }

    @MainActor
    @Test("Журнал сборки не перетекает в другой чат")
    func assemblyLogDoesNotLeak() {
        let state = AppState()
        state.selectedSession = ChatSession(id: "A")
        state.beginContextAssembly(message: "запрос A", projectRoot: "/tmp/a", sessionID: "A")

        #expect(state.contextAssemblyLog != .empty)

        state.selectedSession = ChatSession(id: "B")
        #expect(state.contextAssemblyLog == .empty)
    }

    @MainActor
    @Test("Бейдж цели не показывает шаги чужого чата")
    func headerBadgeDoesNotLeakSteps() {
        let state = AppState()
        state.selectedSession = ChatSession(id: "A")
        state.setSteps([TaskStep(title: "A1", status: .completed)], for: "A")
        #expect(state.currentSteps.map(\.title) == ["A1"])

        state.selectedSession = ChatSession(id: "B")
        #expect(state.currentSteps.isEmpty)
        #expect(!HeaderGoalProgressLogic.shouldShow(
            selectedSession: state.selectedSession,
            goal: nil,
            steps: state.currentSteps
        ))
    }
}
