import Testing
import Foundation
@testable import myCoder

@Suite("ЦЕЛЬ — разбор команды /goal")
struct GoalCommandLogicTests {

    @Test("Просто текст — это создание цели")
    func createFromPlainText() {
        #expect(GoalCommandLogic.parse("/goal сделать рефакторинг") == .create(title: "сделать рефакторинг"))
        #expect(GoalCommandLogic.parse("/goal create собрать билд") == .create(title: "собрать билд"))
    }

    @Test("Жизненный цикл")
    func lifecycleCommands() {
        #expect(GoalCommandLogic.parse("/goal start") == .start)
        #expect(GoalCommandLogic.parse("/goal pause") == .pause)
        #expect(GoalCommandLogic.parse("/goal resume") == .resume)
        #expect(GoalCommandLogic.parse("/goal list") == .list)
        #expect(GoalCommandLogic.parse("/goal delete") == .delete(index: nil))
        #expect(GoalCommandLogic.parse("/goal delete 2") == .delete(index: 2))
    }

    @Test("Не-целевые команды не распознаются")
    func nonGoal() {
        #expect(GoalCommandLogic.isGoalCommand("/remember факт") == false)
        #expect(GoalCommandLogic.parse("привет") == .none)
    }

    @Test("Регистр не важен")
    func caseInsensitive() {
        #expect(GoalCommandLogic.isGoalCommand("/GOAL start") == true)
        #expect(GoalCommandLogic.parse("/Goal Start") == .start)
    }
}

@Suite("ЦЕЛЬ — разбор вердикта адвоката дьявола")
struct GoalVerdictParserTests {

    @Test("Корректный JSON парсится")
    func parsesValid() {
        let v = GoalVerdictParser.parse(#"{"complete": false, "notDone": ["Шаг 2"], "reason": "Шаг 2 не готов"}"#)
        #expect(v?.complete == false)
        #expect(v?.notDone == ["Шаг 2"])
        #expect(v?.reason == "Шаг 2 не готов")
        #expect(v?.valid == true)
    }

    @Test("Не-JSON возвращает nil")
    func invalidNotParsed() {
        #expect(GoalVerdictParser.parse("не json") == nil)
    }

    @Test("Слияние с детерминированной проверкой: план решает полноту")
    func mergedUsesPlanAsGroundTruth() {
        let plan = [
            UserGoal.PlanItem(title: "a", status: .todo),
            UserGoal.PlanItem(title: "b", status: .done)
        ]
        // Модель ошибочно говорит complete=true, но план не полон.
        let model = GoalVerdict(complete: true, notDone: [], reason: "готово", valid: true)
        let merged = GoalVerdictParser.merged(model: model, plan: plan)
        #expect(merged.complete == false)
        #expect(merged.notDone == ["a"])
    }
}
