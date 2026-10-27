import Testing
import Foundation
@testable import myCoder

/// Project memory must survive a restart, stay inspectable, and really reach
/// the model-bound pack. These tests use a real project database on disk where
/// persistence matters and an in-memory one where it does not.
@Suite("Память проекта — SQLite, /remember и пакет контекста")
struct ProjectMemoryStoreTests {

    // MARK: - Fixtures

    private func makeProjectDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ root: URL) {
        ProjectDatabaseManager.evictProject(projectPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func chunk(text: String,
                       files: [String] = [],
                       tags: [String] = [],
                       sourceMessageID: String? = nil,
                       createdAt: Int64 = 1_700_000_000,
                       updatedAt: Int64 = 1_700_000_000) -> ProjectMemoryChunk {
        ProjectMemoryChunk(
            id: ProjectMemoryExtraction.stableID(for: text),
            projectID: "/tmp/project",
            kind: "fact",
            text: text,
            files: files,
            tags: tags,
            sourceMessageID: sourceMessageID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - T1: schema survives a restart

    @Test("Таблица памяти создаётся и переживает перезапуск")
    func schemaSurvivesRestart() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }

        let manager = try ProjectDatabaseManager.manager(forProjectPath: root.path)
        let store = try manager.makeMemoryStore()
        try store.upsert(chunk(text: "решение: хранить настройки в UserDefaults"))

        ProjectDatabaseManager.evictProject(projectPath: root.path)

        let reopened = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeMemoryStore()
        #expect(try reopened.count() == 1)
        #expect(try reopened.all().first?.text == "решение: хранить настройки в UserDefaults")
    }

    @Test("Повторное открытие не ломает схему и не дублирует записи")
    func schemaIsIdempotent() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }

        let first = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeMemoryStore()
        try first.upsert(chunk(text: "факт про проект"))

        ProjectDatabaseManager.evictProject(projectPath: root.path)
        let second = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeMemoryStore()
        try second.upsert(chunk(text: "факт про проект"))

        #expect(try second.count() == 1)
    }

    // MARK: - T2: write/read with files, tags and timestamps

    @Test("Запись и чтение сохраняют файлы, теги и время создания")
    func writeReadKeepsMetadata() throws {
        let manager = try ProjectDatabaseManager.createInMemory(projectPath: "/tmp/memory-t2")
        let store = try manager.makeMemoryStore()

        let original = chunk(
            text: "UserStore.load возвращает 0 для неизвестного id",
            files: ["Sources/UserStore.swift"],
            tags: ["userstore", "load"],
            sourceMessageID: "msg_17",
            createdAt: 100,
            updatedAt: 100
        )
        try store.upsert(original)

        let stored = try #require(try store.all().first)
        #expect(stored.files == ["Sources/UserStore.swift"])
        #expect(stored.tags == ["userstore", "load"])
        #expect(stored.sourceMessageID == "msg_17")

        // Re-remembering the same fact updates it instead of duplicating it,
        // and keeps the original creation time.
        var updated = original
        updated.text = "UserStore.load возвращает 0 для неизвестного id (проверено)"
        updated.updatedAt = 300
        try store.upsert(updated)

        #expect(try store.count() == 1)
        let reread = try #require(try store.all().first)
        #expect(reread.createdAt == 100)
        #expect(reread.updatedAt == 300)
        #expect(reread.text.contains("проверено"))
    }

    @Test("Пустой текст не создаёт запись")
    func emptyTextIsRejected() {
        #expect(ProjectMemoryExtraction.chunk(text: "   ", projectPath: "/tmp/memory") == nil)
    }

    @Test("Опасный путь из текста не попадает в память")
    func unsafePathIsDropped() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-memory-outside-\(UUID().uuidString).swift")
        try "let x = 1".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let fact = try #require(ProjectMemoryExtraction.chunk(
            text: "см. ../\(outside.lastPathComponent)",
            projectPath: root.path
        ))
        #expect(fact.files.isEmpty)
    }

    // MARK: - T3: retrieval by entity/tag

    @Test("Поиск по сущности и тегу возвращает релевантную память")
    func retrievalFindsRelevantChunks() throws {
        let manager = try ProjectDatabaseManager.createInMemory(projectPath: "/tmp/memory-t3")
        let store = try manager.makeMemoryStore()

        let relevant = chunk(
            text: "UserStore живёт в Sources/UserStore.swift",
            files: ["Sources/UserStore.swift"],
            tags: ["userstore"]
        )
        let unrelated = chunk(text: "CI использует GitHub Actions для deploy", tags: ["deploy"])
        try store.upsert(relevant)
        try store.upsert(unrelated)

        let found = try store.search("как работает UserStore.load?")
        #expect(found.map(\.id) == [relevant.id])
        #expect(try store.search("что настроено в deploy?").map(\.id) == [unrelated.id])
    }

    @Test("Ранжирование памяти детерминировано")
    func rankingIsDeterministic() {
        let chunks = [
            chunk(text: "UserStore кэширует значения", tags: ["userstore"], updatedAt: 10),
            chunk(text: "UserStore.load читает кэш", tags: ["userstore", "load"], updatedAt: 20),
            chunk(text: "Другая тема", tags: ["other"], updatedAt: 30)
        ]
        let first = ProjectMemoryRanker.rank(chunks, query: "UserStore.load")
        let second = ProjectMemoryRanker.rank(chunks, query: "UserStore.load")
        #expect(first.map(\.id) == second.map(\.id))
        #expect(!first.isEmpty)
        #expect(first.count <= 5)
    }

    // MARK: - T4: /remember

    @Test("/remember превращается в действие и не уходит модели как текст")
    func rememberSlashCommand() {
        let executor = SlashCommandExecutor(hasGitRepo: false)
        #expect(executor.execute("/remember decision: хранить настройки в UserDefaults")
            == .remember("decision: хранить настройки в UserDefaults"))

        let context = SlashDispatchContext(
            hasGitRepo: false,
            hasRemote: false,
            branch: nil,
            modelID: "m",
            providerID: "p",
            agentMode: "build",
            workspacePath: nil,
            testRunner: nil,
            changedFileCount: 0
        )
        #expect(SlashCommandDispatcher.effects(for: .remember("x"), context: context) == [.clearInput])
    }

    @Test("/remember извлекает вид факта, файлы и теги и сохраняется")
    func rememberExtractsAndStores() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let source = root.appendingPathComponent("UserStore.swift")
        try "final class UserStore {}".write(to: source, atomically: true, encoding: .utf8)

        let fact = try #require(ProjectMemoryExtraction.chunk(
            text: "decision: UserStore.load возвращает 0 в UserStore.swift",
            projectPath: root.path,
            sourceMessageID: "msg_42"
        ))
        #expect(fact.kind == "decision")
        #expect(fact.files == ["UserStore.swift"])
        #expect(fact.tags.contains("userstore"))
        #expect(fact.sourceMessageID == "msg_42")

        let store = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeMemoryStore()
        try store.upsert(fact)
        #expect(try store.count() == 1)
    }

    // MARK: - T5: memory reaches the pack

    @Test("Память попадает в ContextPack со ссылкой на источник")
    func memoryReachesPack() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let source = root.appendingPathComponent("UserStore.swift")
        try """
        final class UserStore {
            func load(id: String) -> Int { 0 }
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let record = FileIndexRecord(
            path: "UserStore.swift",
            hash: "h",
            size: 60,
            lastModified: 1_700_000_000,
            language: "swift",
            searchableText: try String(contentsOf: source, encoding: .utf8)
        )
        let board = ContextBoardBuilder.build(projectPath: root.path, records: [record])
        let memory = chunk(
            text: "UserStore.load всегда возвращает 0",
            files: ["UserStore.swift"],
            tags: ["userstore", "load"],
            sourceMessageID: "msg_42"
        )

        let pack = TurnContextCompiler.compile(
            message: "почему UserStore.load возвращает 0?",
            board: board,
            projectRoot: root.path,
            memories: [memory]
        )
        #expect(pack.memoryIDs == [memory.id])
        #expect(pack.text.contains("## Память проекта"))
        #expect(pack.text.contains("источник: сообщение msg_42"))
        #expect(pack.text.contains("UserStore.load всегда возвращает 0"))
        // The code evidence is still there: memory supplements, not replaces.
        #expect(pack.citations.contains { $0.path == "UserStore.swift" })
    }

    @Test("Память доходит до model-bound текста даже без совпадений в индексе")
    func memoryAloneIsEvidence() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let memory = chunk(text: "сборка идёт через swift build", tags: ["сборка"])

        let preparation = SendContextPreparationLogic.prepare(
            message: "как идёт сборка проекта?",
            records: [],
            projectPath: root.path,
            isEnabled: true,
            memories: [memory]
        )
        #expect(preparation.warning == nil)
        #expect(preparation.pack?.memoryIDs == [memory.id])
        #expect(preparation.modelText.contains("сборка идёт через swift build"))
        #expect(preparation.modelText.contains("сборка идёт"))
    }

    @Test("Сбой чтения памяти виден, но не блокирует отправку")
    func memoryReadFailureIsVisible() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let record = FileIndexRecord(
            path: "A.swift", hash: "h", size: 4, lastModified: 1,
            language: "swift", searchableText: "let a = 1"
        )
        try "let a = 1".write(to: root.appendingPathComponent("A.swift"),
                             atomically: true, encoding: .utf8)

        let preparation = SendContextPreparationLogic.prepare(
            message: "что делает let a?",
            records: [record],
            projectPath: root.path,
            isEnabled: true,
            extraWarning: "память не прочитана"
        )
        #expect(preparation.warning?.contains("память не прочитана") == true)
        #expect(!preparation.modelText.isEmpty)
    }
}
