import Foundation
import Testing
@testable import myCoder

/// User directive 2026-11-03 (п.2): the composer line must name every source
/// that is actually being read. Graph and skills used to be collected silently
/// inside the compiler, so the one-line log stopped at "читаю файлы".
@Suite("Стадии сборки: граф, скиллы, влияние")
struct ContextStageCallbackTests {

    private func project(withSkill: Bool = true) throws -> (root: URL, records: [FileIndexRecord], skills: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let code = "func load() {}\nfunc reload() { load() }\n"
        try code.write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        let skills = root.appendingPathComponent("skills")
        if withSkill {
            try FileManager.default.createDirectory(at: skills.appendingPathComponent("swift"), withIntermediateDirectories: true)
            try "Swift reload review".write(
                to: skills.appendingPathComponent("swift/SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        let records = [FileIndexRecord(
            path: "Store.swift",
            hash: "test",
            size: code.utf8.count,
            lastModified: 0,
            language: "swift",
            searchableText: code
        )]
        return (root, records, skills)
    }

    private func board(_ records: [FileIndexRecord], root: URL) -> ContextBoard {
        ContextBoardBuilder.build(projectPath: root.path, records: records)
    }

    @Test("Компилятор сообщает о скиллах и графе до чтения файлов")
    func reportsSkillsAndGraph() throws {
        let fixture = try project()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var stages: [ContextStageLogLogic.Stage] = []
        _ = TurnContextCompiler.compile(
            message: "reload swift",
            board: board(fixture.records, root: fixture.root),
            projectRoot: fixture.root.path,
            skillsDirectory: fixture.skills,
            records: fixture.records,
            onStage: { stages.append($0) }
        )
        #expect(stages.contains(.skills))
        #expect(stages.contains(.graph))
        // The log must not claim a source that is read later.
        let skillsIndex = try #require(stages.firstIndex(of: .skills))
        let graphIndex = try #require(stages.firstIndex(of: .graph))
        #expect(skillsIndex < graphIndex)
    }

    @Test("Без индекса стадия графа не объявляется")
    func noRecordsMeansNoGraphStage() throws {
        let fixture = try project()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var stages: [ContextStageLogLogic.Stage] = []
        _ = TurnContextCompiler.compile(
            message: "reload",
            board: ContextBoard(projectPath: fixture.root.path, entries: [], builtAt: Date()),
            projectRoot: fixture.root.path,
            records: [],
            onStage: { stages.append($0) }
        )
        #expect(!stages.contains(.graph))
    }

    @Test("Отчёт о зависимостях объявляет стадию влияния")
    func impactStageIsReported() throws {
        let fixture = try project()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let report = ImpactReport(
            triggers: ["удали"],
            affected: [],
            dependents: [],
            fates: [],
            order: [],
            questions: [],
            refs: []
        )
        var stages: [ContextStageLogLogic.Stage] = []
        _ = TurnContextCompiler.compile(
            message: "reload",
            board: board(fixture.records, root: fixture.root),
            projectRoot: fixture.root.path,
            records: fixture.records,
            impact: report,
            onStage: { stages.append($0) }
        )
        #expect(stages.contains(.impact))
    }

    @Test("Стадия влияния имеет собственную честную строку")
    func impactStageHasLine() {
        let line = ContextStageLogLogic.line(for: .impact)
        #expect(!line.isEmpty)
        #expect(!line.contains("\n"))
        #expect(line.lowercased().contains("связ") || line.lowercased().contains("зависим"))
    }

    @Test("Колбэк не ломает компиляцию, если его не передали")
    func callbackIsOptional() throws {
        let fixture = try project()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let pack = TurnContextCompiler.compile(
            message: "reload",
            board: board(fixture.records, root: fixture.root),
            projectRoot: fixture.root.path,
            records: fixture.records
        )
        #expect(!pack.text.isEmpty)
    }
}
