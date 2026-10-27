import Testing
import Foundation
@testable import myCoder

@Suite("Кандидаты контекста — ранжирование вместо полной доски")
struct ContextCandidatesTests {

    private func record(path: String,
                        language: String = "swift",
                        size: Int = 1024,
                        mtime: TimeInterval = 1_700_000_000,
                        text: String? = nil) -> FileIndexRecord {
        FileIndexRecord(path: path,
                        hash: "h-\(path)",
                        size: size,
                        lastModified: mtime,
                        language: language,
                        searchableText: text)
    }

    private let storeSource = """
    import Foundation

    /// Хранилище провайдеров.
    final class ProviderStore {
        private var cache: [String: Int] = [:]

        func load(id: String) -> Int {
            cache[id] ?? 0
        }
    }
    """

    private func board(_ records: [FileIndexRecord]) -> ContextBoard {
        ContextBoardBuilder.build(projectPath: "/tmp/demo", records: records)
    }

    // MARK: - Board metadata

    @Test("Запись доски несёт mtime и номер строки каждого символа")
    func entryCarriesMTimeAndSymbolLines() throws {
        let board = board([record(path: "Sources/Store.swift", text: storeSource)])
        let entry = try #require(board.entries.first)
        #expect(entry.lastModified == 1_700_000_000)
        let load = try #require(entry.symbols.first { $0.name == "load" })
        #expect(load.line == 7)
        let store = try #require(entry.symbols.first { $0.name == "ProviderStore" })
        #expect(store.line == 4)
    }

    @Test("Рендер доски печатает символ со строкой, а не только имя")
    func renderShowsSymbolLine() {
        let board = board([record(path: "Sources/Store.swift", text: storeSource)])
        let text = ContextBoardBuilder.render(board)
        #expect(text.contains("ProviderStore@4"))
        #expect(text.contains("load@7"))
    }

    // MARK: - Ranking

    @Test("Точное совпадение имени выше префикса, префикс выше вхождения в текст")
    func exactBeatsPrefixBeatsToken() {
        let records = [
            record(path: "Sources/A.swift", text: "func store() {}"),
            record(path: "Sources/B.swift", text: "func storeAll() {}"),
            record(path: "Sources/C.swift", text: "let message = \"store\"\nfunc other() {}")
        ]
        let ranked = CandidateRanker.rank(board: board(records), query: "store")
        #expect(ranked.map(\.path) == ["Sources/A.swift", "Sources/B.swift", "Sources/C.swift"])
        #expect(ranked[0].score > ranked[1].score)
        #expect(ranked[1].score > ranked[2].score)
    }

    @Test("Лимит кандидатов соблюдается")
    func limitIsRespected() {
        let records = (0..<20).map { record(path: "Sources/File\($0).swift", text: "func store\($0)() {}") }
        let ranked = CandidateRanker.rank(board: board(records), query: "store", limit: 5)
        #expect(ranked.count == 5)
    }

    @Test("Бюджет байт соблюдается: в кандидаты не попадает лишнее")
    func budgetIsRespected() {
        let records = (0..<10).map {
            record(path: "Sources/File\($0).swift", size: 500, text: "func store\($0)() {}")
        }
        let ranked = CandidateRanker.rank(
            board: board(records),
            query: "store",
            limit: 10,
            budgetBytes: 1_600
        )
        #expect(ranked.count == 3)
    }

    @Test("Секреты, бинарники и слишком большие файлы не становятся кандидатами")
    func unsafeFilesAreNotCandidates() {
        let records = [
            record(path: "Sources/Store.swift", text: storeSource),
            record(path: ".env", text: "SECRET=store"),
            record(path: "bin/tool", language: "binary", text: nil),
            record(path: "Sources/Huge.swift", size: 5_000_000, text: "func store() {}")
        ]
        let ranked = CandidateRanker.rank(board: board(records), query: "store")
        #expect(ranked.map(\.path) == ["Sources/Store.swift"])
    }

    @Test("Свежий файл при равном счёте идёт раньше")
    func newerFileWinsTies() {
        let records = [
            record(path: "Sources/Old.swift", mtime: 1_600_000_000, text: "func store() {}"),
            record(path: "Sources/New.swift", mtime: 1_700_000_000, text: "func store() {}")
        ]
        let ranked = CandidateRanker.rank(board: board(records), query: "store")
        #expect(ranked.map(\.path) == ["Sources/New.swift", "Sources/Old.swift"])
    }

    @Test("Пустая доска — пустой список кандидатов")
    func emptyBoardHasNoCandidates() {
        let ranked = CandidateRanker.rank(board: board([]), query: "store")
        #expect(ranked.isEmpty)
    }

    @Test("Кандидат несёт совпавшие символы с их строками")
    func candidateCarriesMatchedSymbols() throws {
        let ranked = CandidateRanker.rank(board: board([record(path: "Sources/Store.swift", text: storeSource)]),
                                          query: "load")
        let candidate = try #require(ranked.first)
        #expect(candidate.matchedSymbols.contains { $0.name == "load" && $0.line == 7 })
    }
}
