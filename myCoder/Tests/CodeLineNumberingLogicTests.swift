import Testing
import Foundation
@testable import myCoder

/// C4 (жалоба владельца 2026-11-09, скриншот): «зачем двойной набор номера
/// строки?».
///
/// `ContextMaterializer` рендерит код как `42 | let x = …` — это РЕАЛЬНЫЕ
/// номера строк файла, нужные для цитат. `CodeBlockSpoilerView` сверху рисует
/// ещё и свой gutter `1, 2, 3…`, поэтому в чате появлялись два столбца
/// номеров. Чистая логика ниже решает, нужен ли gutter: если номера уже
/// встроены и последовательны — второй столбец не рисуется.
@Suite("Номера строк в кодовых блоках (C4)")
struct CodeLineNumberingLogicTests {

    @Test("Встроенные последовательные номера распознаются")
    func detectsEmbeddedSequentialNumbers() {
        let code = """
        42 | let first = 1
        43 | let second = 2
        44 | let third = 3
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == [42, 43, 44])
    }

    @Test("Пустые строки не ломают распознавание")
    func blankLinesDoNotBreakDetection() {
        let code = """
        7 | func f() {

        8 | }
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == [7, 8])
    }

    @Test("Обычный код без номеров не считается нумерованным")
    func plainCodeIsNotNumbered() {
        let code = """
        let first = 1
        let second = 2
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == nil)
    }

    @Test("Не-последовательные номера не считаются встроенной нумерацией")
    func nonSequentialNumbersAreNotNumbering() {
        let code = """
        10 | let first = 1
        20 | let second = 2
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == nil)
    }

    @Test("Смешанный блок (часть строк без номеров) не нумерованный")
    func mixedBlockIsNotNumbered() {
        let code = """
        1 | let first = 1
        let second = 2
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == nil)
    }

    @Test("Одна строка с номером — ещё не нумерованный блок")
    func singleLineIsNotEnough() {
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: "1 | let x = 1") == nil)
    }

    @Test("Gutter рисуется только для ненумерованного кода и включённой настройки")
    func gutterDecision() {
        let numbered = "5 | a\n6 | b"
        let plain = "a\nb"
        #expect(!CodeLineNumberingLogic.shouldShowGutter(code: numbered, showLineNumbers: true))
        #expect(CodeLineNumberingLogic.shouldShowGutter(code: plain, showLineNumbers: true))
        #expect(!CodeLineNumberingLogic.shouldShowGutter(code: plain, showLineNumbers: false))
    }

    @Test("Diff-блок не принимается за нумерацию")
    func diffIsNotNumbering() {
        let code = """
        + added line
        - removed line
        """
        #expect(CodeLineNumberingLogic.embeddedLineNumbers(in: code) == nil)
    }
}
