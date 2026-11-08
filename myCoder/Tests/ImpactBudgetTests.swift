import Testing
import Foundation
@testable import myCoder

/// The impact pass re-indexes the whole project (`CodeIndexService.ensureIndexed`)
/// on every send, synchronously, with no deadline. On a large project that
/// stalls the send: the stage line froze on "Проверяю связи и зависимости
/// изменяемого кода" and the turn never produced an answer (live run
/// 2026-11-04, chat FF5D0A17). The pass must be bounded: past its budget the
/// turn continues with the graph it already has instead of waiting forever.
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
    func hangingPassReturnsNil() async {
        let started = Date()
        let result = await ImpactBudget.run(budget: .milliseconds(300)) {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            return "late"
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(result == nil, "зависший проход должен вернуть nil, а не ждать")
        #expect(elapsed < 3.0, "бюджет не соблюдён: \(elapsed) c")
    }

    @Test("Нулевой бюджет не запускает работу вовсе")
    func zeroBudgetSkips() async {
        let result = await ImpactBudget.run(budget: .zero) {
            return "never"
        }
        #expect(result == nil)
    }

    @Test("Синхронная работа не блокирует вызывающий актор")
    func syncWorkDoesNotBlockCaller() async {
        // Живой прогон 2026-11-04: report() остался на MainActor, заблокировал
        // его, и /api/state перестал отвечать вовсе. Работа обязана уходить
        // с актора вызывающего.
        let started = Date()
        let result = await ImpactBudget.runSync(budget: .milliseconds(300)) {
            Thread.sleep(forTimeInterval: 5)
            return "late"
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(result == nil, "зависшая синхронная работа должна обрываться")
        #expect(elapsed < 3.0, "вызывающий актор был заблокирован: \(elapsed) c")
    }

    @Test("Бюджет по умолчанию — пять минут (300 с)")
    func defaultBudgetIsFiveMinutes() {
        #expect(ImpactBudget.defaultBudget == 300)
    }
}
