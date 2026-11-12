import Foundation
import Testing
@testable import myCoder

/// Разбиение ответа на прозу, блоки кода и инлайн-картинки
/// (запрос 2026-11-13: картинки показывать инлайн, а не текстом markdown).
@MainActor
@Suite("Разбиение сообщения на прозу, код и картинки")
struct MarkdownMediaSegmentLogicTests {

    @Test("Текст без картинок остаётся одной прозой")
    func plainProse() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "просто ответ\nбез картинок")
        #expect(segments == [.prose("просто ответ\nбез картинок")])
    }

    @Test("Инлайн-картинка вырезается из прозы в свой сегмент")
    func inlineImageSplit() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "Смотри ![схема](img.png) ниже")
        #expect(segments == [
            .prose("Смотри"),
            .image(alt: "схема", source: "img.png"),
            .prose("ниже")
        ])
    }

    @Test("Картинка на отдельной строке даёт сегмент-картинку")
    func standaloneImage() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "![схема](diagram.png)")
        #expect(segments == [.image(alt: "схема", source: "diagram.png")])
    }

    @Test("Несколько картинок сохраняют порядок")
    func multipleImages() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "![a](1.png) и ![b](2.png)")
        #expect(segments == [
            .image(alt: "a", source: "1.png"),
            .prose("и"),
            .image(alt: "b", source: "2.png")
        ])
    }

    @Test("Фенсы кода не трогаются: код с картинко-подобной строкой остаётся кодом")
    func codeBlocksUntouched() {
        let text = """
        до
        ```swift
        // ![не картинка](x.png)
        let a = 1
        ```
        после
        """
        let segments = MarkdownMediaSegmentLogic.segments(from: text)
        #expect(segments.count == 3)
        guard case .code(let language, let code) = segments[1] else {
            Issue.record("expected code block")
            return
        }
        #expect(language == "swift")
        #expect(code.contains("не картинка"))
    }

    @Test("Незакрытый синтаксис картинки во время стриминга остаётся прозой")
    func unclosedImageStaysProse() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "Смотри ![схема](img.png")
        #expect(segments == [.prose("Смотри ![схема](img.png")])
    }

    @Test("proseTexts отдаёт только прозу без картинок")
    func proseTextsExcludeImages() {
        let texts = MarkdownMediaSegmentLogic.proseTexts(from: "до ![x](i.png) после")
        #expect(texts == ["до", "после"])
    }

    @Test("Пустой текст не создаёт сегментов")
    func emptyText() {
        #expect(MarkdownMediaSegmentLogic.segments(from: "").isEmpty)
    }

    @Test("Пустой alt допустим")
    func emptyAlt() {
        let segments = MarkdownMediaSegmentLogic.segments(from: "![](img.png)")
        #expect(segments == [.image(alt: "", source: "img.png")])
    }
}
