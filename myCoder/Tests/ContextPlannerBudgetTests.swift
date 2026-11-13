import Testing
import Foundation
@testable import myCoder

/// The context planner reused `LiveSpecCompletionProvider`, whose timeout is
/// 600 s because a spec interview legitimately takes minutes. A send-time
/// context assembly inherited that budget, so a slow or wedged internal model
/// left the turn "collecting context" for ten minutes with no way out.
/// The planner must have its own short budget and fall back deterministically.
///
/// The suite is deliberately NOT `@MainActor`: it measures a wall-clock
/// timeout, and queueing behind the other main-actor suites delayed the
/// 0.2 s timer past the 5 s assertion under parallel load (2026-11-13).
/// Nothing here touches UI state, so a nonisolated suite is also more honest.
@Suite("Бюджет сборки контекста")
struct ContextPlannerBudgetTests {

    private func context() -> LocalPlannerContext {
        LocalPlannerContextBuilder.build(
            message: "как работает TurnEvidence",
            board: ContextBoard(projectPath: "/tmp/p", entries: [], builtAt: Date()),
            memories: []
        )
    }

    @Test("Зависшая внутренняя модель укладывается в бюджет и даёт fallback")
    func hangingModelFallsBackWithinBudget() async {
        let started = Date()
        let result = await InternalContextPlanner.plan(
            message: "как работает TurnEvidence",
            context: context(),
            budget: 0.2,
            complete: { _ in
                // Never returns: the exact shape of the reported hang.
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return "{}"
            }
        )
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 5, "планировщик не уложился в бюджет: \(elapsed) с")
        guard case .fallback = result.status else {
            Issue.record("ожидался fallback, получено \(result.status)")
            return
        }
        #expect(result.plan == nil)
    }

    @Test("Быстрая модель не обрезается бюджетом")
    func fastModelIsNotCut() async {
        let json = #"{"files":[],"symbols":[],"reasoning":"ok"}"#
        let result = await InternalContextPlanner.plan(
            message: "как работает TurnEvidence",
            context: context(),
            budget: 5,
            complete: { _ in json }
        )
        if case .fallback(let reason) = result.status {
            #expect(!reason.contains("timeout"), "быстрый ответ не должен падать по таймауту")
        }
    }

    @Test("Бюджет по умолчанию не десять минут")
    func defaultBudgetIsShort() {
        #expect(InternalContextPlanner.defaultBudget <= 60,
                "бюджет сборки контекста \(InternalContextPlanner.defaultBudget) с — слишком долго для отправки")
        #expect(InternalContextPlanner.defaultBudget > 0)
    }
}
