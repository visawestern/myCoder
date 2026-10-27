import Testing
import Foundation
@testable import myCoder

@Suite("Материализация контекста и разбивка под окно модели")
struct ContextMaterializerTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-materializer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = (1...40).map { "line \($0)" }.joined(separator: "\n")
        try source.write(to: root.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("Указанные строки попадают в контекст с ссылкой file:line")
    func materializesRequestedRange() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = AtomicTask(
            atomicTask: "Проверить сортировку",
            tddSteps: ["написать тест", "прогнать"],
            acceptance: ["тест зелёный"],
            refs: [TaskReference(path: "Sample.swift", symbol: nil, startLine: 10, endLine: 12, why: nil)],
            knownGaps: []
        )
        let context = try ContextMaterializer.materialize(task: task, projectRoot: root.path)
        #expect(context.contains("## Атомарная задача"))
        #expect(context.contains("Проверить сортировку"))
        #expect(context.contains("TDD"))
        #expect(context.contains("Sample.swift:10-12"))
        #expect(context.contains("line 10"))
        #expect(context.contains("line 12"))
        #expect(!context.contains("line 13"))
    }

    @Test("Ссылка только по символу находит объявление")
    func materializesBySymbol() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try "func target() {}\n".write(to: root.appendingPathComponent("Named.swift"),
                                      atomically: true, encoding: .utf8)

        let task = AtomicTask(
            atomicTask: "Task",
            tddSteps: [],
            acceptance: [],
            refs: [TaskReference(path: "Named.swift", symbol: "target", startLine: nil, endLine: nil, why: nil)],
            knownGaps: []
        )
        let context = try ContextMaterializer.materialize(task: task, projectRoot: root.path)
        #expect(context.contains("Named.swift"))
        #expect(context.contains("func target()"))
    }

    @Test("Несуществующий файл — типизированная ошибка")
    func missingFileFails() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = AtomicTask(
            atomicTask: "Task",
            tddSteps: [],
            acceptance: [],
            refs: [TaskReference(path: "Ghost.swift", symbol: nil, startLine: nil, endLine: nil, why: nil)],
            knownGaps: []
        )
        #expect(throws: LocalCompilerError.self) {
            _ = try ContextMaterializer.materialize(task: task, projectRoot: root.path)
        }
    }

    @Test("Пустые refs дают задачу без блока кода")
    func noRefsNoCode() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = AtomicTask(
            atomicTask: "Проверить гипотезу",
            tddSteps: [],
            acceptance: [],
            refs: [],
            knownGaps: ["нужного файла нет"]
        )
        let context = try ContextMaterializer.materialize(task: task, projectRoot: root.path)
        #expect(context.contains("Проверить гипотезу"))
        #expect(context.contains("Чего не знаем"))
        #expect(!context.contains("## Код"))
    }

    // MARK: - Chunker

    private func bigContext(sections: Int, sectionSize: Int) -> String {
        var text = "## Атомарная задача\nСобрать контекст\n"
        let line = String(repeating: "x", count: 30)
        let lineCount = max(1, sectionSize / 30)
        for index in 0..<sections {
            text += "\n## Блок \(index + 1)\n"
            text += String(repeating: line + "\n", count: lineCount)
        }
        return text
    }

    @Test("Малый контекст остаётся одним чанком")
    func smallContextSingleChunk() throws {
        let chunks = try PromptChunker.chunk(
            context: "## Атомарная задача\nМало\n",
            limitBytes: 10_000
        )
        #expect(chunks.count == 1)
        #expect(chunks.first?.text.contains("Мало") == true)
    }

    @Test("Большой контекст делится на чанки в пределах лимита")
    func largeContextIsSplit() throws {
        let context = bigContext(sections: 6, sectionSize: 400)
        let chunks = try PromptChunker.chunk(context: context, limitBytes: 1_200)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.text.utf8.count <= 1_200)
        }
        #expect(chunks.first?.index == 1)
        #expect(chunks.last?.total == chunks.count)
    }

    @Test("Каждый чанк после первого помечен как продолжение")
    func chunksAreMarked() throws {
        let context = bigContext(sections: 6, sectionSize: 400)
        let chunks = try PromptChunker.chunk(context: context, limitBytes: 1_200)
        for chunk in chunks.dropFirst() {
            #expect(chunk.text.contains("часть"))
            #expect(chunk.text.contains("дожд"))
        }
    }

    @Test("Блок больше лимита делится на части, а не обрезается")
    func oversizedSectionIsSplit() throws {
        let context = bigContext(sections: 1, sectionSize: 5_000)
        let chunks = try PromptChunker.chunk(context: context, limitBytes: 500)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.text.utf8.count <= 500)
        }
        let joined = chunks.map(\.text).joined(separator: "\n")
        #expect(joined.filter { $0 == "x" }.count == 166 * 30)
    }

    @Test("Строка больше лимита — ошибка, данные не теряются молча")
    func singleHugeLineFails() throws {
        let context = "## Атомарная задача\n" + String(repeating: "y", count: 5_000) + "\n"
        #expect(throws: LocalCompilerError.self) {
            _ = try PromptChunker.chunk(context: context, limitBytes: 500)
        }
    }
}
