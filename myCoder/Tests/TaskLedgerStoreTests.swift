import Testing
import Foundation
@testable import myCoder

/// The ledger must capture the task state deterministically, survive a restart,
/// and replace a long raw transcript in the model-bound text.
@Suite("Ledger задачи — состояние, персистентность и замена истории")
struct TaskLedgerStoreTests {

    private func makeProjectDir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ root: URL) {
        ProjectDatabaseManager.evictProject(projectPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func message(_ id: String, _ role: MessageRole, _ content: String) -> Message {
        Message(id: id, role: role, content: content, isFinished: true)
    }

    private func sampleLedger() -> TaskLedger {
        TaskLedger(
            sessionID: "s1",
            projectPath: "/tmp/ledger-project",
            goal: "Добавить поиск по проекту",
            constraints: ["Не трогай UserStore.swift — публичный API должен остаться прежним"],
            decisions: ["decision: используем SQLite FTS5"],
            entities: ["UserStore", "SearchIndex"],
            artifacts: ["Sources/UserStore.swift"],
            openQuestions: ["Почему падает UserStore.load?"],
            coverage: ["m1", "m2"],
            sourceMessageIDs: ["m1", "m2"],
            updatedAt: 1_700_000_000
        )
    }

    // MARK: - T1: fields, verbatim constraints, source ids

    @Test("Ledger хранит цель, ограничения дословно, решения, сущности, артефакты и вопросы")
    func extractionKeepsEveryField() {
        let messages = [
            message("m1", .user, "Нужно добавить поиск. Не трогай UserStore.swift — must keep the public API."),
            message("m2", .assistant, "decision: используем SQLite FTS5"),
            message("m3", .user, "Почему падает UserStore.load?\nTODO: проверить гонку")
        ]
        let memory = ProjectMemoryChunk(
            id: "mem_1", projectID: "/tmp/p", kind: "decision",
            text: "decision: кэш только в памяти",
            files: [], tags: ["cache"], sourceMessageID: "m2",
            createdAt: 10, updatedAt: 10
        )

        let ledger = TaskLedgerExtraction.build(
            sessionID: "s1",
            projectPath: "/tmp/p",
            goal: "Добавить поиск по проекту",
            messages: messages,
            memories: [memory]
        )

        #expect(ledger.goal == "Добавить поиск по проекту")
        // Constraints are stored as the user wrote them, not paraphrased.
        #expect(ledger.constraints == [messages[0].content])
        #expect(ledger.decisions.contains("decision: используем SQLite FTS5"))
        #expect(ledger.decisions.contains("decision: кэш только в памяти"))
        #expect(ledger.entities.contains("UserStore"))
        #expect(ledger.artifacts.contains("UserStore.swift"))
        #expect(ledger.openQuestions.contains("Почему падает UserStore.load?"))
        #expect(ledger.openQuestions.contains("TODO: проверить гонку"))
        #expect(ledger.sourceMessageIDs.contains("m1"))
        #expect(ledger.sourceMessageIDs.contains("m3"))
        #expect(ledger.coverage.contains("m1"))
        #expect(ledger.coverage.contains("m2"))
        #expect(!ledger.isEmpty)
    }

    @Test("Короткая история без фактов не даёт пустых полей-призраков")
    func smallTalkIsNotInvented() {
        let ledger = TaskLedgerExtraction.build(
            sessionID: "s2",
            projectPath: "/tmp/p",
            goal: nil,
            messages: [message("m1", .user, "привет")]
        )
        #expect(ledger.goal == "привет")
        #expect(ledger.constraints.isEmpty)
        #expect(ledger.decisions.isEmpty)
        #expect(ledger.entities.isEmpty)
        #expect(ledger.openQuestions.isEmpty)
    }

    @Test("Новый ledger не забывает ограничение из прошлого после обрезки истории")
    func mergeKeepsPrunedConstraints() {
        let previous = TaskLedger(
            sessionID: "s1", projectPath: "/tmp/p",
            goal: "Цель",
            constraints: ["Не трогай миграции"],
            decisions: [], entities: [], artifacts: [], openQuestions: [],
            coverage: ["old1"], sourceMessageIDs: ["old1"], updatedAt: 100
        )
        let ledger = TaskLedgerExtraction.build(
            sessionID: "s1",
            projectPath: "/tmp/p",
            goal: nil,
            messages: [message("new1", .user, "добавь кнопку")],
            previous: previous,
            now: 200
        )
        #expect(ledger.constraints == ["Не трогай миграции"])
        #expect(ledger.goal == "Цель")
        #expect(ledger.sourceMessageIDs.contains("old1"))
        #expect(ledger.sourceMessageIDs.contains("new1"))
        #expect(ledger.updatedAt == 200)
    }

    // MARK: - T2: persistence

    @Test("Ledger переживает перезапуск")
    func ledgerSurvivesRestart() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }

        var ledger = sampleLedger()
        ledger.projectPath = root.path

        let store = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeLedgerStore()
        try store.save(ledger)

        ProjectDatabaseManager.evictProject(projectPath: root.path)

        let reopened = try ProjectDatabaseManager.manager(forProjectPath: root.path).makeLedgerStore()
        #expect(try #require(try reopened.load(sessionID: "s1")) == ledger)
        #expect(try reopened.count() == 1)
    }

    @Test("Повторное сохранение обновляет строку, а не дублирует её")
    func saveIsUpsert() throws {
        let manager = try ProjectDatabaseManager.createInMemory(projectPath: "/tmp/ledger-t2")
        let store = try manager.makeLedgerStore()

        var ledger = sampleLedger()
        try store.save(ledger)
        ledger.openQuestions = ["Новый вопрос?"]
        ledger.updatedAt = 300
        try store.save(ledger)

        #expect(try store.count() == 1)
        #expect(try store.load(sessionID: "s1")?.openQuestions == ["Новый вопрос?"])
    }

    // MARK: - T3: pack and history replacement

    @Test("Ledger попадает в ContextPack дословно и со ссылкой на задачу")
    func ledgerReachesPack() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let ledger = sampleLedger()

        let preparation = SendContextPreparationLogic.prepare(
            message: "продолжай",
            records: [],
            projectPath: root.path,
            isEnabled: true,
            ledger: ledger
        )

        let pack = try #require(preparation.pack)
        #expect(pack.ledgerSummary == ledger.summaryText)
        #expect(pack.text.contains("## Состояние задачи"))
        #expect(pack.text.contains("Не трогай UserStore.swift — публичный API должен остаться прежним"))
        #expect(pack.text.contains("decision: используем SQLite FTS5"))
        #expect(preparation.modelText.contains("## Состояние задачи"))
    }

    @Test("Ledger заменяет сырую историю только когда она действительно длинная")
    func replacementPolicy() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let ledger = sampleLedger()

        let preparation = SendContextPreparationLogic.prepare(
            message: "продолжай",
            records: [],
            projectPath: root.path,
            isEnabled: true,
            ledger: ledger
        )

        #expect(!SendContextPreparationLogic.replacesRawHistory(preparation, priorTurnCount: 2))
        #expect(SendContextPreparationLogic.replacesRawHistory(preparation, priorTurnCount: 20))
        #expect(TaskLedgerPolicy.minimumTurnsToReplace == 6)

        // No ledger → raw history is never silently dropped.
        let withoutLedger = SendContextPreparationLogic.prepare(
            message: "продолжай",
            records: [],
            projectPath: root.path,
            isEnabled: true
        )
        #expect(!SendContextPreparationLogic.replacesRawHistory(withoutLedger, priorTurnCount: 20))
    }

    @Test("В model-bound тексте с ledger нет сырых двадцати сообщений")
    func rawHistoryIsNotAppendedTwice() throws {
        let root = try makeProjectDir()
        defer { cleanup(root) }
        let ledger = sampleLedger()

        let preparation = SendContextPreparationLogic.prepare(
            message: "что дальше?",
            records: [],
            projectPath: root.path,
            isEnabled: true,
            ledger: ledger
        )
        let text = preparation.modelText
        #expect(text.contains("## Запрос"))
        #expect(text.contains("## Состояние задачи"))
        #expect(!text.contains("assistant:"))
        #expect(!text.contains("user:"))
    }

    // MARK: - T4: wiring

    @Test("Отправка строит и сохраняет ledger, а ветки провайдеров его используют")
    func sendWiring() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("TaskLedgerExtraction.build("))
        #expect(source.contains("TaskLedgerStore.load("))
        #expect(source.contains("TaskLedgerStore.save(taskLedger)"))
        #expect(source.contains("ledger: taskLedger"))
        #expect(source.contains("SendContextPreparationLogic.replacesRawHistory("))
    }

    @Test("Схема ledger живёт в проектной БД, а не в отдельном хранилище")
    func schemaWiring() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/ProjectDatabaseManager.swift")
        #expect(source.contains("func makeLedgerStore()"))
        let store = try RepoRoot.sourceText("myCoder/Sources/Services/TaskLedgerStore.swift")
        #expect(store.contains("task_ledgers"))
        #expect(store.contains("createSchema"))
    }
}
