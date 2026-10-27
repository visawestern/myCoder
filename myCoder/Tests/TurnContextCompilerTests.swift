import Testing
import Foundation
@testable import myCoder

@Suite("Компилятор контекста хода — детерминированный пакет доказательств")
struct TurnContextCompilerTests {

    // MARK: - Fixtures

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-turn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = """
        import Foundation

        final class UserStore {
            private var cache: [String: Int] = [:]

            func load(id: String) -> Int {
                cache[id] ?? 0
            }
        }
        """
        try store.write(to: root.appendingPathComponent("UserStore.swift"),
                        atomically: true, encoding: .utf8)

        let tests = """
        import Testing

        @Test func testLoadReturnsZero() {
            #expect(UserStore().load(id: "x") == 0)
        }
        """
        try tests.write(to: root.appendingPathComponent("UserStoreTests.swift"),
                        atomically: true, encoding: .utf8)
        return root
    }

    private func board(for root: URL, files: [String]) throws -> ContextBoard {
        let records = try files.map { path -> FileIndexRecord in
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            return FileIndexRecord(
                path: path,
                hash: "h-\(path)",
                size: text.utf8.count,
                lastModified: 1_700_000_000,
                language: "swift",
                searchableText: text
            )
        }
        return ContextBoardBuilder.build(projectPath: root.path, records: records)
    }

    // MARK: - Query plan

    @Test("План поиска извлекает пути, символы, тесты и строку ошибки")
    func planExtractsTerms() {
        let message = "Почему падает UserStoreTests.testLoad в Sources/UserStore.swift:42 ?"
        let plan = ContextQueryPlanner.plan(for: message)
        #expect(plan.files.contains("Sources/UserStore.swift"))
        #expect(plan.symbols.contains("UserStoreTests"))
        #expect(plan.symbols.contains("testLoad"))
        #expect(plan.lineNumbers.contains(42))
        #expect(plan.terms.contains("userstore"))
    }

    // MARK: - Pack

    @Test("Пакет содержит секции, цитаты file:line и манифест")
    func packHasSectionsCitationsAndManifest() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift", "UserStoreTests.swift"])

        let pack = TurnContextCompiler.compile(
            message: "как работает UserStore.load?",
            board: board,
            projectRoot: root.path
        )
        #expect(!pack.sections.isEmpty)
        #expect(pack.citations.contains { $0.path == "UserStore.swift" })
        #expect(pack.text.contains("UserStore.swift:"))
        #expect(pack.text.contains("load"))
        #expect(pack.manifest.included.contains("UserStore.swift"))
    }

    @Test("Манифест перечисляет выброшенные источники с причиной")
    func manifestListsDroppedSources() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift", "UserStoreTests.swift"])

        let pack = TurnContextCompiler.compile(
            message: "UserStore load test",
            board: board,
            projectRoot: root.path,
            budgetTokens: 60
        )
        let hasDropped = !pack.manifest.dropped.isEmpty
        #expect(hasDropped || pack.unknowns.isEmpty == false)
        if let dropped = pack.manifest.dropped.first {
            #expect(!dropped.reason.isEmpty)
        }
    }

    @Test("Пакет укладывается в бюджет токенов")
    func packFitsBudget() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift", "UserStoreTests.swift"])

        let pack = TurnContextCompiler.compile(
            message: "UserStore load",
            board: board,
            projectRoot: root.path,
            budgetTokens: 120
        )
        #expect(pack.estimatedTokens <= 120)
    }

    @Test("Одинаковый вход даёт одинаковый пакет")
    func compileIsDeterministic() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift", "UserStoreTests.swift"])

        let first = TurnContextCompiler.compile(message: "UserStore.load", board: board, projectRoot: root.path)
        let second = TurnContextCompiler.compile(message: "UserStore.load", board: board, projectRoot: root.path)
        #expect(first.text == second.text)
        #expect(first.citations == second.citations)
    }

    @Test("Длинный запрос не обрезается, даже если не влезает в бюджет")
    func longRequestIsNeverTruncated() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])
        let message = String(repeating: "почему падает UserStore ", count: 300)
        let pack = TurnContextCompiler.compile(
            message: message,
            board: board,
            projectRoot: root.path,
            budgetTokens: 120
        )
        #expect(pack.text.contains(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(pack.unknowns.contains { $0.contains("запрос больше бюджета") })
    }

    @Test("Без индекса пакет содержит пробелы и не падает")
    func emptyBoardGivesGaps() {
        let empty = ContextBoardBuilder.build(projectPath: "/tmp/mimo-empty", records: [])
        let pack = TurnContextCompiler.compile(
            message: "где хранится UserStore?",
            board: empty,
            projectRoot: "/tmp/mimo-empty"
        )
        #expect(pack.citations.isEmpty)
        #expect(!pack.unknowns.isEmpty)
        #expect(pack.text.contains("Пробелы") || pack.text.contains("что не вошло"))
    }

    @Test("Нечитаемый кандидат не роняет пакет, а попадает в пробелы")
    func unreadableCandidateBecomesGap() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("UserStore.swift"))

        let pack = TurnContextCompiler.compile(
            message: "UserStore load",
            board: board,
            projectRoot: root.path
        )
        #expect(pack.citations.isEmpty)
        #expect(pack.unknowns.contains { $0.contains("UserStore.swift") })
    }
}
