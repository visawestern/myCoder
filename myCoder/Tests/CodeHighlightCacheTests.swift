import AppKit
import SwiftUI
import Testing
@testable import myCoder

/// Кэш подсветки кода: одна и та же пара (код, язык, палитра) не должна
/// токенизироваться и перекрашиваться на каждый body-eval спойлера.
 /// Счётчики кэша глобальные, поэтому тесты идут последовательно:
 /// параллельный запуск смешивает `highlightBuilds` соседних проверок.
@Suite("Кэш подсветки кода (CodeSyntaxHighlighter)", .serialized)
struct CodeHighlightCacheTests {

    init() {
        CodeSyntaxHighlighter.resetHighlightCache()
    }

    private func palette(_ accent: Color) -> CodePalette {
        CodePalette(
            background: .white,
            headerBackground: .white,
            border: .white,
            text: .black,
            comment: .gray,
            keyword: accent,
            string: accent,
            number: accent,
            function: accent,
            type: accent,
            constant: accent,
            decorator: accent,
            lineNumber: .gray,
            diffAdded: .green,
            diffRemoved: .red,
            diffMeta: .yellow
        )
    }

    @Test("Повторный вызов не строит подсветку заново и возвращает то же значение")
    func repeatedCallHitsCache() {
        let p = palette(.blue)
        let first = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: p)
        let buildsAfterFirst = CodeSyntaxHighlighter.highlightBuilds
        let second = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: p)
        #expect(first == second)
        #expect(CodeSyntaxHighlighter.highlightBuilds == buildsAfterFirst)
        #expect(CodeSyntaxHighlighter.highlightHits == 1)
    }

    @Test("Разные коды не делят одну запись")
    func differentCodeSeparateEntries() {
        let p = palette(.blue)
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: p)
        _ = CodeSyntaxHighlighter.cachedAttributed("let y = 2", language: "swift", palette: p)
        #expect(CodeSyntaxHighlighter.highlightBuilds == 2)
    }

    @Test("Разные палитры не делят одну запись")
    func differentPalettesSeparateEntries() {
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: palette(.blue))
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: palette(.red))
        #expect(CodeSyntaxHighlighter.highlightBuilds == 2)
    }

    @Test("Регистр языка не плодит записи: swift/Swift/ SWIFT — одна запись")
    func languageCaseIsNormalized() {
        let p = palette(.blue)
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: p)
        let builds = CodeSyntaxHighlighter.highlightBuilds
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "Swift", palette: p)
        _ = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: " SWIFT ", palette: p)
        #expect(CodeSyntaxHighlighter.highlightBuilds == builds)
        #expect(CodeSyntaxHighlighter.highlightHits == 2)
    }

    @Test("Результат кэша совпадает с прямой подсветкой")
    func cachedMatchesDirect() {
        let p = palette(.blue)
        let direct = CodeSyntaxHighlighter.attributed("let x = 1", language: "swift", palette: p)
        let cached = CodeSyntaxHighlighter.cachedAttributed("let x = 1", language: "swift", palette: p)
        #expect(cached == direct)
    }

    @Test("resetHighlightCache очищает счётчики")
    func resetClears() {
        let p = palette(.blue)
        _ = CodeSyntaxHighlighter.cachedAttributed("a", language: "swift", palette: p)
        CodeSyntaxHighlighter.resetHighlightCache()
        #expect(CodeSyntaxHighlighter.highlightBuilds == 0)
        #expect(CodeSyntaxHighlighter.highlightHits == 0)
        _ = CodeSyntaxHighlighter.cachedAttributed("a", language: "swift", palette: p)
        #expect(CodeSyntaxHighlighter.highlightBuilds == 1)
    }
}
