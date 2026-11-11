import Testing
import Foundation
@testable import myCoder

/// Дедупликация на уровне собранного пакета: один файл — один блок, повторы
/// памяти и зависимостей не раздувают итоговый текст перед отправкой модели.
@MainActor
@Suite("Дедупликация в собранном пакете")
struct TurnContextPackDedupIntegrationTests {

    // MARK: - Fixtures

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-dedup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = """
        import Foundation

        final class UserStore {
            private var cache: [String: Int] = [:]

            func load(id: String) -> Int {
                cache[id] ?? 0
            }
        }
        """ + String(repeating: "// слой-наполнитель, чтобы в файле были строки за пределами блока символа\n",
                     count: 100)
        try store.write(to: root.appendingPathComponent("UserStore.swift"),
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

    private func makeMemory(id: String, text: String, sourceMessageID: String) -> ProjectMemoryChunk {
        ProjectMemoryChunk(
            id: id,
            projectID: "p",
            kind: "fact",
            text: text,
            files: [],
            tags: [],
            sourceMessageID: sourceMessageID,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }

    // MARK: - Dedup в пакете

    @Test("Кандидат и зависимость одного файла дают один блок")
    func candidateAndDependencySameFileSingleBlock() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])

        let impact = ImpactReport(
            triggers: ["изменение"],
            affected: [],
            dependents: [],
            fates: [],
            order: [],
            // Непустые вопросы делают отчёт непустым — иначе блок зависимостей
            // не выполняется вовсе (impact.isEmpty).
            questions: ["нужно проверить влияние на вызывающий код"],
            // Диапазон вне блока кандидата (строки ~1-60) — иначе guard по
            // цитатам вообще не добавит секцию зависимости.
            refs: [TaskReference(path: "UserStore.swift", symbol: nil,
                                   startLine: 70, endLine: 90, why: "зависимость")]
        )
        let pack = TurnContextCompiler.compile(
            message: "UserStore load",
            board: board,
            projectRoot: root.path,
            impact: impact
        )

        let fileSections = pack.sections.filter { ContextDeduplication.filePath(in: $0) != nil }
        #expect(fileSections.count == 1)
        #expect(pack.manifest.included.filter { $0 == "UserStore.swift" }.count == 1)
        #expect(pack.manifest.dropped.contains { $0.reason.contains("дубликат файла") })
        #expect(pack.citations.filter { $0.path == "UserStore.swift" }.count <= 1)
        // Секция-зависимость не попала в итоговый текст.
        #expect(pack.text.contains("— зависимость") == false)
    }

    @Test("Идентичные повторы памяти попадают в пакет один раз")
    func duplicateMemoriesOnce() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])

        let text = "факт: UserStore держит кэш и читает его через load"
        let memories = [
            makeMemory(id: "m1", text: text, sourceMessageID: "a"),
            makeMemory(id: "m2", text: text, sourceMessageID: "b")
        ]
        let pack = TurnContextCompiler.compile(
            message: "UserStore кэш",
            board: board,
            projectRoot: root.path,
            memories: memories
        )

        #expect(pack.memoryIDs.count == 1)
        let memorySection = pack.sections.first { $0.title == "Память проекта" }
        #expect(memorySection != nil)
        #expect(memorySection?.body.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count == 1)
    }

    @Test("Повтор одинакового файла среди кандидатов — один блок")
    func duplicateCandidateSamePathOnce() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])

        // Два кандидата одного пути: доска с дублем записи пути.
        let duplicated = ContextBoard(
            projectPath: root.path,
            entries: [board.entries[0], board.entries[0]],
            builtAt: .distantPast
        )
        let pack = TurnContextCompiler.compile(
            message: "UserStore load",
            board: duplicated,
            projectRoot: root.path
        )

        let fileSections = pack.sections.filter { ContextDeduplication.filePath(in: $0) != nil }
        #expect(fileSections.count <= 1)
        #expect(pack.manifest.included.filter { $0 == "UserStore.swift" }.count <= 1)
    }

    @Test("Запрос сохраняется, даже если совпадает с памятью")
    func requestNeverDropped() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = try board(for: root, files: ["UserStore.swift"])

        let message = "UserStore load"
        let memories = [
            makeMemory(id: "m1", text: message, sourceMessageID: "a")
        ]
        let pack = TurnContextCompiler.compile(
            message: message,
            board: board,
            projectRoot: root.path,
            memories: memories
        )

        let requestSection = pack.sections.first { $0.title == "Запрос" }
        #expect(requestSection?.body == message)
    }
}
