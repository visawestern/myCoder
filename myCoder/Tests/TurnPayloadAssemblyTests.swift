import Testing
import Foundation
@testable import myCoder

/// The user's design (2026-11-03): every message must carry, in this order,
/// the system instruction, the point context (memory + chat + code graph +
/// index + project instructions + matching skills) and the user's request —
/// and all of it must be visible in the context tabs.
///
/// These tests pin the contract at the compiler level, where it is testable
/// without a UI.
@MainActor
@Suite("Полный пакет хода: системная инструкция + контекст + запрос")
struct TurnPayloadAssemblyTests {

    // MARK: - Fixtures

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        func load() {}
        func reload() { load() }
        """.write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        try "Use TDD for every change.".write(
            to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8
        )
        let skillDir = root.appendingPathComponent("skills/swift", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "Swift concurrency review checklist.".write(
            to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return root
    }

    private func records(for root: URL) throws -> [FileIndexRecord] {
        let text = try String(contentsOf: root.appendingPathComponent("Store.swift"), encoding: .utf8)
        return [FileIndexRecord(path: "Store.swift", hash: "h", size: text.utf8.count,
                                lastModified: 1_700_000_000, language: "swift",
                                searchableText: text)]
    }

    private func board(_ records: [FileIndexRecord], root: URL) -> ContextBoard {
        ContextBoardBuilder.build(projectPath: root.path, records: records)
    }

    // MARK: - Order

    @Test("Аудит-текст начинается с системной инструкции, затем контекст, затем запрос")
    func auditTextStartsWithSystemInstruction() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "как работает reload?",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "Ты агент проекта.",
            skillsDirectory: root.appendingPathComponent("skills")
        )
        let audit = pack.auditText
        let systemIndex = try #require(audit.range(of: "## Системная инструкция"))
        let requestIndex = try #require(audit.range(of: "## Запрос"))
        #expect(systemIndex.lowerBound < requestIndex.lowerBound)
        #expect(audit.contains("Ты агент проекта."))
        #expect(audit.contains("как работает reload?"))
    }

    @Test("Системная инструкция не дублируется в тексте, который уходит модели")
    func systemPromptIsNotDuplicatedOnTheWire() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "reload",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "УНИКАЛЬНЫЙ_МАРКЕР_ИНСТРУКЦИИ",
            skillsDirectory: root.appendingPathComponent("skills")
        )
        // The system instruction travels as its own system message, so the
        // user-message payload must not repeat it.
        #expect(!pack.text.contains("УНИКАЛЬНЫЙ_МАРКЕР_ИНСТРУКЦИИ"))
        #expect(pack.auditText.contains("УНИКАЛЬНЫЙ_МАРКЕР_ИНСТРУКЦИИ"))
        #expect(pack.systemPrompt == "УНИКАЛЬНЫЙ_МАРКЕР_ИНСТРУКЦИИ")
    }

    // MARK: - Evidence sources

    @Test("Инструкции проекта и подходящий скилл попадают в пакет")
    func projectInstructionsAndSkillAreInThePack() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "проверь swift код в reload",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "sys",
            skillsDirectory: root.appendingPathComponent("skills")
        )
        #expect(pack.auditText.contains("Use TDD for every change."))
        #expect(pack.auditText.contains("Swift concurrency review checklist."))
        #expect(pack.sections.contains { $0.title.hasPrefix("Инструкции проекта") })
        #expect(pack.sections.contains { $0.title.hasPrefix("Скилл:") })
    }

    @Test("Нерелевантный скилл не подмешивается")
    func unrelatedSkillIsNotAttached() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "reload",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "sys",
            skillsDirectory: root.appendingPathComponent("skills")
        )
        #expect(!pack.auditText.contains("Swift concurrency review checklist."))
    }

    @Test("Граф кода даёт соседей символа, а не только его имя")
    func codeGraphSectionCarriesNeighbors() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "reload",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "sys",
            skillsDirectory: nil,
            records: records
        )
        let graph = try #require(pack.sections.first { $0.title == "Граф кода" })
        #expect(graph.body.contains("reload"))
        #expect(graph.body.contains("load"))
    }

    @Test("Без графа пакет всё равно собирается")
    func packWorksWithoutGraph() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = try records(for: root)

        let pack = TurnContextCompiler.compile(
            message: "reload",
            board: board(records, root: root),
            projectRoot: root.path,
            systemPrompt: "sys"
        )
        #expect(!pack.sections.isEmpty)
        #expect(pack.text.contains("reload"))
    }

    // MARK: - Honest degradation

    @Test("Отсутствие инструкций и скиллов не создаёт пустых секций")
    func noEmptySectionsWhenSourcesAreAbsent() {
        let empty = ContextBoardBuilder.build(projectPath: "/tmp/mimo-none", records: [])
        let pack = TurnContextCompiler.compile(
            message: "ничего",
            board: empty,
            projectRoot: "/tmp/mimo-none",
            systemPrompt: "sys"
        )
        #expect(!pack.sections.contains { $0.title.hasPrefix("Инструкции проекта") })
        #expect(!pack.sections.contains { $0.title.hasPrefix("Скилл:") })
        #expect(!pack.sections.contains { $0.title == "Граф кода" })
    }
}
