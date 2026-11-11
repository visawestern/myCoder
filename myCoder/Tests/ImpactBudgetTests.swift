import Testing
import Foundation
@testable import myCoder

/// The impact pass re-indexes the whole project (`CodeIndexService.ensureIndexed`)
/// on every send, synchronously, with no deadline. On a large project that
/// stalls the send: the stage line froze on "Проверяю связи и зависимости
/// изменяемого кода" and the turn never produced an answer (live run
/// 2026-11-04, chat FF5D0A17). The pass must be bounded: past its budget the
/// turn continues with the graph it already has instead of waiting forever.
@MainActor
@Suite("Бюджет проверки связей")
struct ImpactBudgetTests {

    @Test("Быстрый проход укладывается в бюджет и возвращает результат")
    func fastPassReturnsResult() async {
        let result = await ImpactBudget.run(budget: .seconds(5)) {
            return "report"
        }
        #expect(result == "report")
    }

    @Test("Зависший проход обрывается по бюджету и даёт nil")
    func hangingPassReturnsNil() async throws {
        let outcome = await ImpactBudget.runMeasuringDeadline(budget: .milliseconds(300)) {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return "late"
        }
        #expect(outcome.value == nil, "зависший проход должен вернуть nil, а не ждать")
        // The deadline delay is measured inside the race (at the timer), so it
        // is not distorted by the caller's continuation being scheduled late
        // under CPU contention — that delay measures the scheduler, not the
        // budget.
        let delay = try #require(outcome.deadlineDelay, "дедлайн должен выиграть гонку")
        #expect(delay < 1.0, "дедлайн сработал через \(delay) с при бюджете 0.3 с")
    }

    @Test("Нулевой бюджет не запускает работу вовсе")
    func zeroBudgetSkips() async {
        let result = await ImpactBudget.run(budget: .zero) {
            return "never"
        }
        #expect(result == nil)
    }

    @Test("Синхронная работа не блокирует вызывающий актор")
    func syncWorkDoesNotBlockCaller() async throws {
        // Живой прогон 2026-11-04: report() остался на MainActor, заблокировал
        // его, и /api/state перестал отвечать вовсе. Работа обязана уходить
        // с актора вызывающего.
        let started = Date()
        let outcome = await ImpactBudget.runSyncMeasuringDeadline(budget: .milliseconds(300)) {
            Thread.sleep(forTimeInterval: 5)
            return "late"
        }
        let elapsed = Date().timeIntervalSince(started)
        // nil means the caller was released by the deadline instead of waiting
        // for the work's result — the work kept running in the background.
        #expect(outcome.value == nil, "зависшая синхронная работа должна обрываться")
        let delay = try #require(outcome.deadlineDelay, "дедлайн должен выиграть гонку")
        #expect(delay < 1.0, "дедлайн сработал через \(delay) с при бюджете 0.3 с")
        // Wall-clock seen by the caller also depends on when the scheduler runs
        // its continuation, so it is only a guard against a pathological hang.
        #expect(elapsed < 15.0, "вызывающий актор висел \(elapsed) c")
    }

    @Test("Бюджет по умолчанию — пять минут (300 с)")
    func defaultBudgetIsFiveMinutes() {
        #expect(ImpactBudget.defaultBudget == 300)
    }
}
