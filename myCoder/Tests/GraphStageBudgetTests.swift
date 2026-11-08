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
@Suite("Бюджет стадии графа кода")
struct GraphStageBudgetTests {

    @Test("Зависшее построение графа не держит ход дольше бюджета")
    func hangingGraphIsBounded() async {
        let started = Date()
        let result: String? = await ImpactBudget.runSync(budget: .milliseconds(250)) {
            Thread.sleep(forTimeInterval: 5)
            return "graph"
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(result == nil)
        #expect(elapsed < 4.8, "стадия графа держала ход \(elapsed) c (работа 5 с)")
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
