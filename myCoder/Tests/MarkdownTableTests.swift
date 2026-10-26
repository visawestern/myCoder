import Testing
import Foundation
@testable import myCoder

@Suite("Markdown Tables & Code Copy")
struct MarkdownTableTests {

    private func rows(of block: MarkdownText.Block) -> [[String]]? {
        if case .table(let rows) = block { return rows }
        return nil
    }

    @Test("Parses a standard markdown table, skipping the separator row")
    func parsesStandardTable() {
        let md = """
        | Параметр | Значение |
        |---|---|
        | Модель | MiMo-v2.5 |
        | Окно контекста | 1 000 000 токенов |
        """
        let view = MarkdownText(text: md)
        let table = view.parseMarkdown().compactMap { rows(of: $0) }.first
        #expect(table != nil)
        #expect(table?.count == 3) // header + 2 data rows
        #expect(table?[0] == ["Параметр", "Значение"])
        #expect(table?[1] == ["Модель", "MiMo-v2.5"])
        #expect(table?[2] == ["Окно контекста", "1 000 000 токенов"])
    }

    @Test("Table does not swallow the following paragraph")
    func tableStopsAtFence() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |\n\nТекст после таблицы"
        let view = MarkdownText(text: md)
        let blocks = view.parseMarkdown()
        #expect(blocks.contains { rows(of: $0) != nil })
        #expect(blocks.contains { if case .paragraph(let p) = $0, p == "Текст после таблицы" { return true }; return false })
    }

    @Test("Separator-only row is excluded from cells")
    func separatorRemoved() {
        let md = "| A | B |\n| :--- | ---: |\n| x | y |"
        let view = MarkdownText(text: md)
        let table = view.parseMarkdown().compactMap { rows(of: $0) }.first
        #expect(table?.count == 2) // header + 1 data row, separator dropped
        #expect(table?[0] == ["A", "B"])
        #expect(table?[1] == ["x", "y"])
    }
}
