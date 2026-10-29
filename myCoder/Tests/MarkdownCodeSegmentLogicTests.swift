import Foundation
import Testing
@testable import myCoder

/// A chat answer must keep its block order when fenced code is lifted out of
/// the prose surface into its own spoiler (user report 2026-10-29).
@Suite("Разбиение сообщения на прозу и блоки кода")
struct MarkdownCodeSegmentLogicTests {

    @Test("Проза, код и снова проза сохраняют порядок")
    func keepsDocumentOrder() {
        let text = """
        intro paragraph

        ```python
        print("hi")
        ```

        outro paragraph
        """
        let segments = MarkdownCodeSegmentLogic.segments(from: text)
        #expect(segments.count == 3)

        guard case .prose(let first) = segments[0] else {
            Issue.record("expected prose first")
            return
        }
        #expect(first == "intro paragraph")

        guard case .code(let language, let code) = segments[1] else {
            Issue.record("expected code second")
            return
        }
        #expect(language == "python")
        #expect(code == "print(\"hi\")")

        guard case .prose(let last) = segments[2] else {
            Issue.record("expected prose last")
            return
        }
        #expect(last == "outro paragraph")
    }

    @Test("Несколько блоков кода идут в порядке появления")
    func multipleCodeBlocks() {
        let text = """
        before
        ```bash
        echo one
        ```
        between
        ```python
        print("two")
        ```
        after
        """
        let segments = MarkdownCodeSegmentLogic.segments(from: text)
        #expect(segments.count == 5)

        let languages = segments.compactMap { segment -> String? in
            if case .code(let language, _) = segment { return language }
            return nil
        }
        #expect(languages == ["bash", "python"])

        let prose = segments.compactMap { segment -> String? in
            if case .prose(let value) = segment { return value }
            return nil
        }
        #expect(prose == ["before", "between", "after"])
    }

    @Test("Незакрытый fence во время стриминга остаётся кодом")
    func unclosedFenceIsCode() {
        let text = """
        Смотри пример:
        ```python
        def hello():
            print("still streaming")
        """
        let segments = MarkdownCodeSegmentLogic.segments(from: text)
        #expect(segments.count == 2)
        guard case .code(let language, let code) = segments[1] else {
            Issue.record("expected code block")
            return
        }
        #expect(language == "python")
        #expect(code.contains("still streaming"))
    }

    @Test("Текст без fence остаётся одной прозой")
    func plainTextStaysProse() {
        let segments = MarkdownCodeSegmentLogic.segments(from: "просто ответ\nбез кода")
        #expect(segments == [.prose("просто ответ\nбез кода")])
    }

    @Test("Сообщение только из кода не теряет блок")
    func codeOnlyMessage() {
        let segments = MarkdownCodeSegmentLogic.segments(from: "```swift\nlet x = 1\n```")
        #expect(segments == [.code(language: "swift", code: "let x = 1")])
    }

    @Test("Пустой текст не создаёт пустых сегментов")
    func emptyTextHasNoSegments() {
        #expect(MarkdownCodeSegmentLogic.segments(from: "").isEmpty)
        #expect(MarkdownCodeSegmentLogic.segments(from: "  \n\n ").isEmpty)
    }

    @Test("Язык fence обрезается от пробелов")
    func languageIsTrimmed() {
        let segments = MarkdownCodeSegmentLogic.segments(from: "```  python  \npass\n```")
        guard case .code(let language, _) = segments.first else {
            Issue.record("expected code block")
            return
        }
        #expect(language == "python")
    }
}
