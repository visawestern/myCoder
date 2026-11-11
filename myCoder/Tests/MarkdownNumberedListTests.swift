import Foundation
import Testing
@testable import myCoder

/// Numbered enumerations in model answers must render with real line breaks:
/// (1) a numbered item that starts its own line after a prose line must NOT be
/// glued into the paragraph, and (2) single newlines inside plain prose stay
/// visible instead of being joined with a space (user report 2026-10-30).
@MainActor
@Suite("Markdown — переносы нумерованных перечислений")
struct MarkdownNumberedListTests {

    private func kinds(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.map { block in
            switch block {
            case .paragraph(let t): return "p:" + t
            case .numberedItem(let n, let t): return "n\(n):" + t
            case .bulletItem(let t): return "b:" + t
            default: return "other"
            }
        }
    }

    @Test("Строка '1.' после текста не склеивается с абзацем")
    func numberedItemAfterProseDoesNotGlue() {
        let text = "Основные детали:\n1. Левая панель\n2. Основная область\n3. Нижняя часть"
        let blocks = MarkdownDocumentParser.parse(text)
        #expect(kinds(blocks) == [
            "p:Основные детали:",
            "n1:Левая панель",
            "n2:Основная область",
            "n3:Нижняя часть"
        ])
    }

    @Test("Одиночный перенос строки в прозе сохраняется (не склеивается пробелом)")
    func singleNewlineInProseIsPreserved() {
        let text = "Первая строка\nвторая строка"
        let blocks = MarkdownDocumentParser.parse(text)
        #expect(blocks.count == 1)
        if case .paragraph(let content) = blocks[0] {
            #expect(content.contains("\n"))
        } else {
            Issue.record("expected paragraph")
        }
    }

    @Test("Нумерованный список в начале документа остаётся списком")
    func pureNumberedListStaysList() {
        let text = "1. Один\n2. Два"
        let blocks = MarkdownDocumentParser.parse(text)
        #expect(kinds(blocks) == ["n1:Один", "n2:Два"])
    }
}
