import Testing
import Foundation
@testable import myCoder

/// Owner design (2026-11-04): after the big model finishes its answer, the
/// internal model re-reviews the work as a devil's advocate. Below 95/100
/// with an unfinished plan and a standing "don't stop until the plan is
/// done" order, the analysis goes back into the model automatically; the
/// loop stops only when the user's help is critically required or the depth
/// cap is hit. These tests pin the pure logic of that gate.
@MainActor
@Suite("Гейт качества ответа — адвокат дьявола")
struct AnswerQualityGateTests {

    private func item(_ id: String, _ status: String) -> PlanTodoItem {
        PlanTodoItem(id: id, title: id, status: status,
                     todoStatus: PlanTodoBridge.todoStatus(for: status),
                     dependsOn: [], acceptanceCriteria: [], isActive: status == "running")
    }

    private let lowVerdictJSON = """
    Разбор выполнен.
    ```json
    {"score": 87, "findings": ["фикс применён"], "missing": ["тесты не прогнаны", "UI не обновлён"], "requiresUser": false, "reason": "план не закрыт"}
    ```
    """

    // MARK: - Standing order detection

    @Test("Приказ «не останавливайся пока план не выполнится» распознаётся в RU и EN")
    func detectsNoStopOrder() {
        #expect(AnswerQualityGate.userOrderedNoStop(in: "Не останавливайся пока весь план не выполнится"))
        #expect(AnswerQualityGate.userOrderedNoStop(in: "не останавливайся пока не доделаешь всё до конца"))
        #expect(AnswerQualityGate.userOrderedNoStop(in: "продолжай без пауз, пока план не выполнен полностью"))
        #expect(AnswerQualityGate.userOrderedNoStop(in: "don't stop until the whole plan is done"))
        #expect(AnswerQualityGate.userOrderedNoStop(in: "Do not stop until every task is complete."))
        #expect(!AnswerQualityGate.userOrderedNoStop(in: "объясни, почему падает тест"))
        #expect(!AnswerQualityGate.userOrderedNoStop(in: "сначала останови движок, потом чини"))
        #expect(!AnswerQualityGate.userOrderedNoStop(in: "стоп, я передумал"))
    }

    // MARK: - Plan completeness

    @Test("План выполнен, когда нет открытых задач")
    func planCompleteness() {
        #expect(AnswerQualityGate.planIsComplete(items: []), "нет плана — ждать нечего")
        #expect(AnswerQualityGate.planIsComplete(items: [item("T1", "done"), item("T2", "skipped")]))
        #expect(!AnswerQualityGate.planIsComplete(items: [item("T1", "done"), item("T2", "pending")]))
        #expect(!AnswerQualityGate.planIsComplete(items: [item("T1", "running")]))
        #expect(!AnswerQualityGate.planIsComplete(items: [item("T1", "failed")]))
        #expect(!AnswerQualityGate.planIsComplete(items: [item("T1", "blocked")]))
    }

    // MARK: - Verdict parsing

    @Test("Вердикт вытаскивается из JSON, даже завёрнутого в markdown")
    func parsesVerdict() throws {
        let verdict = try #require(AnswerQualityGate.parseVerdict(from: lowVerdictJSON))
        #expect(verdict.score == 87)
        #expect(verdict.findings == ["фикс применён"])
        #expect(verdict.missing == ["тесты не прогнаны", "UI не обновлён"])
        #expect(verdict.requiresUser == false)
        #expect(verdict.reason == "план не закрыт")
    }

    @Test("Мусорный ответ — nil, а не выдуманная оценка")
    func garbageIsNotAVerdict() {
        #expect(AnswerQualityGate.parseVerdict(from: "не могу оценить") == nil)
        #expect(AnswerQualityGate.parseVerdict(from: "{\"score\": \"высокая\"}") == nil)
        #expect(AnswerQualityGate.parseVerdict(from: "") == nil)
    }

    @Test("Оценка зажата в 0…100")
    func scoreIsClamped() throws {
        let high = try #require(AnswerQualityGate.parseVerdict(from: #"{"score": 140}"#))
        #expect(high.score == 100)
        let low = try #require(AnswerQualityGate.parseVerdict(from: #"{"score": -7}"#))
        #expect(low.score == 0)
    }

    // MARK: - Decision

    private let lowVerdict = QualityGateVerdict(
        score: 87, findings: ["фикс применён"],
        missing: ["тесты не прогнаны"], requiresUser: false, reason: "план не закрыт"
    )
    private var openPlan: [PlanTodoItem] { [item("T1", "done"), item("T2", "running")] }
    private var closedPlan: [PlanTodoItem] { [item("T1", "done")] }

    @Test("Оценка ≥ 95 или выполненный план — принимаем")
    func acceptWhenGoodOrDone() {
        if case .accept = AnswerQualityGate.decision(
            verdict: QualityGateVerdict(score: 95, findings: [], missing: [],
                                        requiresUser: false, reason: ""),
            planComplete: false, noStopOrdered: true) {} else {
            Issue.record("95 должен приниматься")
        }
        if case .accept = AnswerQualityGate.decision(
            verdict: lowVerdict, planComplete: true, noStopOrdered: true) {} else {
            Issue.record("выполненный план должен приниматься")
        }
    }

    @Test("< 95, план не готов, приказ был — авто-продолжение с полным разбором")
    func continueWhenBelowThresholdAndOrdered() throws {
        let decision = AnswerQualityGate.decision(
            verdict: lowVerdict, planComplete: false, noStopOrdered: true)
        guard case .continueTurn(let feedback) = decision else {
            Issue.record("ожидалось авто-продолжение")
            return
        }
        #expect(feedback.contains("87"))
        #expect(feedback.contains("команды останавливаться не было"))
        #expect(feedback.contains("тесты не прогнаны"))
    }

    @Test("Без приказа авто-продолжения нет — оценка показывается, ход завершается")
    func noAutoContinueWithoutOrder() {
        if case .accept = AnswerQualityGate.decision(
            verdict: lowVerdict, planComplete: false, noStopOrdered: false) {} else {
            Issue.record("без приказа гейт не должен продолжать сам")
        }
    }

    @Test("Критическая необходимость пользователя перебивает авто-продолжение")
    func userInterventionStopsTheLoop() {
        let verdict = QualityGateVerdict(
            score: 40, findings: [], missing: ["нет доступов"],
            requiresUser: true, reason: "нужны креденшелы")
        if case .askUser = AnswerQualityGate.decision(
            verdict: verdict, planComplete: false, noStopOrdered: true) {} else {
            Issue.record("requiresUser должен останавливать цикл")
        }
    }

    // MARK: - Runner

    @Test("Раннер гонит вердикт через внутреннюю модель и решает")
    func runnerEvaluatesWithCompletion() async throws {
        let outcome = await AnswerQualityGateRunner.evaluate(
            request: "почини план",
            answer: "готово, всё сделано",
            planItems: openPlan,
            noStopOrdered: true
        ) { _ in lowVerdictJSON }
        #expect(outcome.verdict?.score == 87)
        guard case .continueTurn = outcome.decision else {
            Issue.record("ожидалось авто-продолжение")
            return
        }
    }

    @Test("Промпт ревьюера содержит запрос, ответ и план")
    func reviewerPromptCarriesEverything() {
        let messages = AnswerQualityGate.verdictPrompt(
            request: "запрос пользователя",
            answer: "ответ модели",
            planText: "[done] T1: готово\n[running] T2: работа"
        )
        #expect(messages.first?.role == "system")
        #expect(messages.last?.content.contains("запрос пользователя") == true)
        #expect(messages.last?.content.contains("ответ модели") == true)
        #expect(messages.last?.content.contains("[running] T2") == true)
    }

    @Test("Нет внутренней модели или мусорный ответ — гейт честно пропускается")
    func runnerSkipsHonestlyWhenModelUnavailable() async {
        let outcome = await AnswerQualityGateRunner.evaluate(
            request: "запрос", answer: "ответ", planItems: openPlan,
            noStopOrdered: true
        ) { _ in throw InternalModelRunner.NoModelError() }
        #expect(outcome.verdict == nil)
        guard case .accept = outcome.decision else {
            Issue.record("пропуск должен быть решением accept с причиной")
            return
        }
    }

    @Test("Выполненный план — анализ не запускается вообще")
    func runnerSkipsWhenPlanComplete() async {
        var called = false
        let outcome = await AnswerQualityGateRunner.evaluate(
            request: "запрос", answer: "ответ", planItems: closedPlan,
            noStopOrdered: true
        ) { _ in
            called = true
            return lowVerdictJSON
        }
        #expect(!called, "готовый план не должен тратить вызов модели")
        #expect(outcome.verdict == nil)
    }

    @Test("Видимая запись о вердикте содержит оценку и решение")
    func visibleNote() throws {
        let verdict = lowVerdict
        let note = AnswerQualityGate.note(
            for: verdict,
            decision: .continueTurn(feedback: "…"))
        #expect(note.contains("87"))
        #expect(note.contains("адвокат дьявола"))
    }
}
