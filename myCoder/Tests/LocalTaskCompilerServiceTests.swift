import Testing
import Foundation
@testable import myCoder

@Suite("Компилятор атомарной задачи — разбор и валидация ответа локальной модели")
struct LocalTaskCompilerServiceTests {

    // MARK: - Parsing

    @Test("Валидный JSON разбирается в атомарную задачу")
    func parsesValidJSON() throws {
        let json = """
        {
          "atomicTask": "Добавить сортировку задач по дедлайну",
          "tdd": {"required": true, "steps": ["написать тест", "прогнать", "реализовать"]},
          "acceptance": ["тест зелёный"],
          "refs": [
            {"path": "Sources/TaskOrdering.swift", "symbol": "sort(tasks:)", "startLine": 10, "endLine": 40, "why": "логика"}
          ],
          "knownGaps": ["нет тестов"]
        }
        """
        let task = try AtomicTaskParser.parse(json)
        #expect(task.atomicTask == "Добавить сортировку задач по дедлайну")
        #expect(task.tddSteps == ["написать тест", "прогнать", "реализовать"])
        #expect(task.acceptance == ["тест зелёный"])
        #expect(task.refs.count == 1)
        #expect(task.refs.first?.path == "Sources/TaskOrdering.swift")
        #expect(task.refs.first?.symbol == "sort(tasks:)")
        #expect(task.refs.first?.startLine == 10)
        #expect(task.refs.first?.endLine == 40)
        #expect(task.knownGaps == ["нет тестов"])
    }

    @Test("Пустой atomicTask — ошибка missingField")
    func emptyAtomicTaskFails() {
        #expect(throws: LocalCompilerError.self) {
            _ = try AtomicTaskParser.parse(#"{"atomicTask": "", "refs": []}"#)
        }
    }

    @Test("Некорректный JSON без ссылок — ошибка invalidJSON")
    func invalidJSONFails() {
        #expect(throws: LocalCompilerError.self) {
            _ = try AtomicTaskParser.parse("не json вовсе")
        }
    }

    @Test("Свободная форма с path:line разбирается в задачу со ссылками")
    func freeFormWithReferencesIsParsed() throws {
        let text = """
        Сделай сортировку задач по дедлайну.
        Sources/TaskOrdering.swift:10-40 — здесь логика сравнения
        """
        let task = try AtomicTaskParser.parse(text)
        #expect(task.atomicTask.contains("Сделай сортировку"))
        #expect(task.refs.count == 1)
        #expect(task.refs.first?.path == "Sources/TaskOrdering.swift")
        #expect(task.refs.first?.startLine == 10)
        #expect(task.refs.first?.endLine == 40)
    }

    @Test("Пустой массив refs — валидная задача без кода")
    func emptyRefsIsValid() throws {
        let task = try AtomicTaskParser.parse(#"{"atomicTask": "Проверить гипотезу", "refs": []}"#)
        #expect(task.refs.isEmpty)
        #expect(task.atomicTask == "Проверить гипотезу")
    }

    @Test("Ссылка на файл вне проекта — ошибка unknownReference")
    func unknownReferenceFails() {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [
                FileIndexRecord(path: "Sources/App.swift", hash: "h", size: 10,
                                lastModified: 1, language: "swift", searchableText: "let x = 1")
            ]
        )
        let json = #"{"atomicTask": "Task", "refs": [{"path": "Sources/Ghost.swift"}]}"#
        #expect(throws: LocalCompilerError.self) {
            _ = try LocalTaskCompilerService.validate(task: try AtomicTaskParser.parse(json), board: board)
        }
    }

    @Test("Ссылка на существующий файл проходит валидацию")
    func knownReferencePasses() throws {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [
                FileIndexRecord(path: "Sources/App.swift", hash: "h", size: 10,
                                lastModified: 1, language: "swift", searchableText: "let x = 1")
            ]
        )
        let json = #"{"atomicTask": "Task", "refs": [{"path": "Sources/App.swift"}]}"#
        let task = try AtomicTaskParser.parse(json)
        #expect(throws: Never.self) {
            try LocalTaskCompilerService.validate(task: task, board: board)
        }
    }

    // MARK: - Compile pipeline

    private final class StubTransport: LocalCompilerTransporting, @unchecked Sendable {
        let answer: String
        init(answer: String) { self.answer = answer }
        func complete(candidate: LocalModelCandidate, prompt: String, system: String?) async throws -> String {
            answer
        }
    }

    @Test("Компиляция возвращает материализованный код с номерами строк")
    func compileMaterializesContext() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-compile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = (1...12).map { "line \($0)" }.joined(separator: "\n")
        try source.write(to: root.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)

        let board = ContextBoardBuilder.build(
            projectPath: root.path,
            records: [
                FileIndexRecord(path: "Sample.swift", hash: "h", size: 10,
                                lastModified: 1, language: "swift", searchableText: source)
            ]
        )
        let answer = #"{"atomicTask": "Task", "refs": [{"path": "Sample.swift", "startLine": 2, "endLine": 3}]}"#
        let runner = LocalModelRunner(
            directory: LocalModelDirectory(candidates: [
                LocalModelCandidate(providerID: "p", providerName: "P", baseURL: "http://x", apiKey: nil, model: "m")
            ]),
            transport: StubTransport(answer: answer)
        )
        let service = LocalTaskCompilerService(board: board, runner: runner)

        let compiled = try await service.compile(userRequest: "продолжай", planNode: nil, projectRoot: root.path)
        #expect(compiled.context.contains("2 | line 2"))
        #expect(compiled.context.contains("Sample.swift:2-3"))
        #expect(compiled.task.atomicTask == "Task")
    }

    // MARK: - Prompt

    @Test("Промпт компилятора содержит запрос, доску и запрет писать код")
    func promptContainsEverything() throws {
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/demo",
            records: [
                FileIndexRecord(path: "Sources/App.swift", hash: "h", size: 10,
                                lastModified: 1, language: "swift",
                                searchableText: "/// Хранилище\nfinal class ProviderStore {}\n")
            ]
        )
        let prompt = LocalCompilerPromptBuilder.build(
            userRequest: "сделай сортировку",
            board: board,
            planNode: nil
        )
        #expect(prompt.system.contains("JSON"))
        #expect(prompt.system.lowercased().contains("код"))
        #expect(prompt.user.contains("сделай сортировку"))
        #expect(prompt.user.contains("Sources/App.swift"))
        #expect(prompt.user.contains("ProviderStore"))
    }

    @Test("Нода плана попадает в промпт компилятора")
    func planNodeIsIncluded() throws {
        let board = ContextBoardBuilder.build(projectPath: "/tmp/demo", records: [])
        let node = PlanTodoItem(id: "T2", title: "Точечный контекст", status: "pending",
                                todoStatus: "pending", dependsOn: [], acceptanceCriteria: ["пак непустой"],
                                isActive: true)
        let prompt = LocalCompilerPromptBuilder.build(userRequest: "продолжай", board: board, planNode: node)
        #expect(prompt.user.contains("T2"))
        #expect(prompt.user.contains("Точечный контекст"))
        #expect(prompt.user.contains("пак непустой"))
    }
}
