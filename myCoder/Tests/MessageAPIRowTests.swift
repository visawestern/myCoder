import Testing
import Foundation
@testable import myCoder

/// `/api/messages` used to drop the very evidence the context feature exists
/// to produce: `contextSummary`, the compiled point context and the raw wire
/// responses never left the app. These tests pin the row contract so the
/// context pipeline is verifiable over HTTP instead of by reading the UI.
@Suite("Строка /api/messages отдаёт контекст")
struct MessageAPIRowTests {

    private func message(
        content: String = "ответ",
        contextSummary: String? = nil,
        parts: [MessagePartContent] = [],
        rawResponses: [String]? = nil
    ) -> Message {
        Message(
            role: .assistant,
            content: content,
            parts: parts,
            isFinished: true,
            rawResponses: rawResponses,
            contextSummary: contextSummary
        )
    }

    @Test("contextSummary попадает в строку ответа")
    func contextSummaryIsExposed() {
        let row = MessageAPIRowLogic.row(
            for: message(contextSummary: "Собрано: 3 файла, 2 воспоминания")
        )
        #expect(row["contextSummary"] as? String == "Собрано: 3 файла, 2 воспоминания")
    }

    @Test("Скомпилированный контекст отдаётся как отдельное поле")
    func compiledContextIsExposed() {
        let pack = "СИСТЕМНАЯ ИНСТРУКЦИЯ\n---\nТОЧЕЧНЫЙ КОНТЕКСТ\n---\nЗАПРОС"
        let row = MessageAPIRowLogic.row(
            for: message(parts: [.compiledContext(pack)])
        )
        #expect(row["compiledContext"] as? String == pack)
    }

    @Test("Сырые ответы провода отдаются списком")
    func rawResponsesAreExposed() {
        let row = MessageAPIRowLogic.row(
            for: message(rawResponses: ["сырой 1", "сырой 2"])
        )
        #expect(row["rawResponses"] as? [String] == ["сырой 1", "сырой 2"])
    }

    @Test("Пустые значения не засоряют строку")
    func emptyValuesAreOmitted() {
        let row = MessageAPIRowLogic.row(for: message())
        #expect(row["contextSummary"] == nil)
        #expect(row["compiledContext"] == nil)
        #expect(row["rawResponses"] == nil)
    }

    @Test("Базовые поля не теряются")
    func baseFieldsSurvive() {
        let row = MessageAPIRowLogic.row(for: message(content: "готово"))
        #expect(row["role"] as? String == "assistant")
        #expect(row["content"] as? String == "готово")
        #expect(row["isFinished"] as? Bool == true)
    }
}
