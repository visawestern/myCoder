import Foundation
import Testing
@testable import myCoder

/// A failed tool call must come back to the model with the error AND the
/// correct call syntax, so the model can retry instead of guessing again
/// (user directive 2026-10-29: "при ошибке json в инструменте возвращалась
/// не только ошибка но и пример вызова с правильным синтаксисом").
@MainActor
@Suite("Подсказка синтаксиса при ошибке инструмента")
struct WebToolSyntaxExampleTests {

    @Test("Ошибка JSON включает правильный пример вызова")
    func jsonErrorIncludesSyntaxExample() {
        let message = WebToolProtocolEmulator.validationResultText(
            for: .incompleteJSON,
            callName: "read_file"
        )
        #expect(message.contains("validation error: incompleteJSON"))
        #expect(message.contains("Correct call syntax"))
        #expect(message.contains("read_file"))
        // The schema placeholder should be present, not just the bare error.
        #expect(message.contains("\"path\""))
    }

    @Test("Канонический алиас резолвится в пример вызова")
    func aliasResolvesToCanonicalExample() {
        let message = WebToolProtocolEmulator.validationResultText(
            for: .incompleteJSON,
            callName: "Read"
        )
        #expect(message.contains("read_file"))
        #expect(message.contains("\"path\""))
    }

    @Test("Неизвестный инструмент: ошибка без примера (схема отсутствует)")
    func unknownToolHasNoExample() {
        let message = WebToolProtocolEmulator.validationResultText(
            for: .unknownTool("frobnicate"),
            callName: "frobnicate"
        )
        #expect(message.contains("validation error: unknownTool"))
        #expect(message.contains("frobnicate"))
        #expect(!message.contains("Correct call syntax"))
    }

    @Test("Выход за пределы проекта тоже получает пример синтаксиса")
    func pathEscapeIncludesExample() {
        let message = WebToolProtocolEmulator.validationResultText(
            for: .pathEscapesProject("/etc/passwd"),
            callName: "edit_file"
        )
        #expect(message.contains("validation error: pathEscapesProject"))
        #expect(message.contains("/etc/passwd"))
        #expect(message.contains("Correct call syntax"))
        #expect(message.contains("edit_file"))
        #expect(message.contains("\"old\""))
    }
}
