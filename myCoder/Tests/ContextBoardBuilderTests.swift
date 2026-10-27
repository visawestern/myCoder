import Testing
import Foundation
@testable import myCoder

@Suite("Context board — структурная карта проекта для локальной модели")
struct ContextBoardBuilderTests {

    private func record(path: String,
                        language: String = "swift",
                        size: Int = 1024,
                        text: String? = nil) -> FileIndexRecord {
        FileIndexRecord(path: path,
                        hash: "h-\(path)",
                        size: size,
                        lastModified: 1_700_000_000,
                        language: language,
                        searchableText: text)
    }

    private let swiftSource = """
    import Foundation

    /// Хранилище провайдеров.
    final class ProviderStore {
        private var cache: [String: Int] = [:]

        func load(id: String) -> Int {
            cache[id] ?? 0
        }
    }
    """

    @Test("Доска содержит по записи на каждый индексируемый файл")
    func boardHasOneEntryPerFile() {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [
                record(path: "Sources/App.swift", text: swiftSource),
                record(path: "Sources/Store.swift", text: "import Foundation\nstruct Store {}\n")
            ]
        )
        #expect(board.entries.count == 2)
        #expect(board.entries.map(\.path) == ["Sources/App.swift", "Sources/Store.swift"])
        #expect(board.projectPath == "/tmp/demo")
    }

    @Test("Символы, импорты и документация извлекаются из файла")
    func entryCarriesSymbolsImportsAndDoc() {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [record(path: "Sources/App.swift", text: swiftSource)]
        )
        let entry = board.entries.first
        #expect(entry != nil)
        let names = entry?.symbols.map(\.name) ?? []
        #expect(names.contains("ProviderStore"))
        #expect(names.contains("load"))
        #expect(entry?.imports.contains("Foundation") == true)
        #expect(entry?.doc?.contains("Хранилище провайдеров") == true)
    }

    @Test("Секреты и бинарные файлы не попадают в доску")
    func secretsAndBinariesAreExcluded() {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [
                record(path: "Sources/App.swift", text: swiftSource),
                record(path: ".env", text: "SECRET=1"),
                record(path: "certs/server.pem", text: "-----BEGIN-----"),
                record(path: "bin/tool", language: "binary", text: nil)
            ]
        )
        #expect(board.entries.map(\.path) == ["Sources/App.swift"])
    }

    @Test("Рендер доски показывает путь, символы и импорты")
    func renderShowsStructure() {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [record(path: "Sources/App.swift", text: swiftSource)]
        )
        let text = ContextBoardBuilder.render(board)
        #expect(text.contains("Sources/App.swift"))
        #expect(text.contains("ProviderStore"))
        #expect(text.contains("Foundation"))
        #expect(text.contains("swift"))
    }

    @Test("Пустой проект даёт пустую доску без ошибок")
    func emptyBoard() {
        let board = ContextBoardBuilder.build(projectPath: "/tmp/demo", records: [])
        #expect(board.entries.isEmpty)
        #expect(ContextBoardBuilder.render(board).isEmpty)
    }

    @Test("Количество символов на файл ограничивается")
    func symbolsAreCapped() {
        let many = (0..<50).map { "func symbol\($0)() {}" }.joined(separator: "\n")
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [record(path: "Sources/Many.swift", text: many)],
            maxSymbolsPerFile: 5
        )
        #expect(board.entries.first?.symbols.count == 5)
    }
}
