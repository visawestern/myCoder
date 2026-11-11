import Testing
import Foundation
@testable import myCoder

/// Сырой JSON вердикта цели не должен показываться в пузыре: он превращается
/// в чип со статусом и спойлер с конкретными пунктами.
@MainActor
@Suite("Вердикт цели — чип и спойлер")
struct GoalVerdictPresentationLogicTests {

    @Test("Чистый JSON вердикта распознаётся")
    func parsesPlainJSON() {
        let json = #"{"complete": false, "notDone": ["пункт 1", "пункт 2"], "reason": "не всё готово"}"#
        let presentation = GoalVerdictPresentationLogic.presentation(in: json)
        #expect(presentation?.complete == false)
        #expect(presentation?.notDone == ["пункт 1", "пункт 2"])
        #expect(presentation?.reason == "не всё готово")
        #expect(presentation?.title == "Цель не выполнена")
        #expect(presentation?.subtitle.contains("2") == true)
    }

    @Test("JSON в ```json-фенсе распознаётся")
    func parsesFencedJSON() {
        let text = """
        ```json
        {"complete": true, "notDone": [], "reason": "всё сделано"}
        ```
        """
        let presentation = GoalVerdictPresentationLogic.presentation(in: text)
        #expect(presentation?.complete == true)
        #expect(presentation?.title == "Цель выполнена")
        #expect(presentation?.reason == "всё сделано")
    }

    @Test("JSON с текстом вокруг не считается вердиктом")
    func proseAroundJSONIsNotVerdict() {
        let text = "Вот вердикт: {\"complete\": false, \"notDone\": [], \"reason\": \"x\"}"
        #expect(GoalVerdictPresentationLogic.presentation(in: text) == nil)
    }

    @Test("Неверный JSON не считается вердиктом")
    func invalidJSONIsNotVerdict() {
        #expect(GoalVerdictPresentationLogic.presentation(in: "{\"foo\": 1}") == nil)
        #expect(GoalVerdictPresentationLogic.presentation(in: "просто ответ") == nil)
    }

    @Test("Один невыполненный пункт — корректная подпись")
    func singleItemSubtitle() {
        let json = #"{"complete": false, "notDone": ["тест не написан"], "reason": "нет теста"}"#
        let presentation = GoalVerdictPresentationLogic.presentation(in: json)
        #expect(presentation?.subtitle == "Не готов 1 пункт")
    }
}
