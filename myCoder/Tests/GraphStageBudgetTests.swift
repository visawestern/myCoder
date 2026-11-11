import Testing
import Foundation
@testable import myCoder

/// Стадия «Строю граф кода» вызывала `TurnEvidence.graph` →
/// `CodeIndexService.search`, а тот на каждом ходе переиндексирует ВЕСЬ
/// проект (`index(store:...)`) без предела. На живом проекте (996 файлов)
/// стадия висела минутами, и ход не доходил до модели (живой прогон
/// 2026-11-04, чат A587ACA5).
///
/// Граф — необязательные улики: по истечении бюджета ход идёт дальше с тем,
/// что уже собрано, и честно пишет пробел.
@MainActor
@Suite("Бюджет стадии графа кода")
struct GraphStageBudgetTests {

    @Test("Зависшее построение графа не держит ход дольше бюджета")
    func hangingGraphIsBounded() async throws {
        let outcome = await ImpactBudget.runSyncMeasuringDeadline(budget: .milliseconds(250)) {
            Thread.sleep(forTimeInterval: 5)
            return "graph"
        }
        #expect(outcome.value == nil)
        // The deadline delay is measured at the timer inside the race, so it
        // is not distorted by the cooperative pool scheduling the caller's
        // continuation late under CPU contention.
        let delay = try #require(outcome.deadlineDelay, "дедлайн должен выиграть гонку")
        #expect(delay < 1.0, "стадия графа держала дедлайн \(delay) c (бюджет 0.25 c)")
    }

    @Test("Быстрый граф возвращается как обычно")
    func fastGraphReturns() async {
        let result: String? = await ImpactBudget.runSync(budget: .seconds(5)) { "graph" }
        #expect(result == "graph")
    }

    @Test("Компилятор сообщает пробел, когда граф не успел")
    func compilerStatesGapWhenGraphTimesOut() {
        // Контракт рендера: пустой граф превращается в явный пробел, а не в
        // молчаливое отсутствие секции.
        let section = TurnEvidence.graphGap(reason: "бюджет исчерпан")
        #expect(section.title == "Граф кода")
        #expect(section.body.contains("бюджет исчерпан"))
    }
}
