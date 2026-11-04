import Testing
import Foundation
@testable import myCoder

/// Owner design (2026-11-04): the context assembler picks "how to do this
/// kind of task" instructions according to the prompt. The internal model
/// already does this when assigned (`LocalQueryPlan.instructions`); this
/// catalog is the deterministic floor for turns without an internal model —
/// instructions must never be empty just because the planner fell back.
@Suite("Каталог инструкций задачи")
struct TaskInstructionCatalogTests {

    @Test("Интент классифицируется по словам запроса")
    func intentClassification() {
        #expect(TaskInstructionCatalog.intent(for: "исправь ошибку в отправке") == .fix)
        #expect(TaskInstructionCatalog.intent(for: "почини падающий тест") == .fix)
        #expect(TaskInstructionCatalog.intent(for: "fix the broken pipeline") == .fix)
        #expect(TaskInstructionCatalog.intent(for: "отрефактори хранилище") == .refactor)
        #expect(TaskInstructionCatalog.intent(for: "переделай способ хранения кадров") == .refactor)
        #expect(TaskInstructionCatalog.intent(for: "refactor the frame store") == .refactor)
        #expect(TaskInstructionCatalog.intent(for: "напиши тест на ранжирование") == .test)
        #expect(TaskInstructionCatalog.intent(for: "добавь кнопку экспорта") == .add)
        #expect(TaskInstructionCatalog.intent(for: "объясни как работает компилятор контекста") == .explain)
        #expect(TaskInstructionCatalog.intent(for: "расскажи про архитектуру") == .explain)
    }

    @Test("Инструкции по интенту не пустые и ограничены")
    func instructionsByIntent() {
        for intent in [LocalQueryIntent.fix, .refactor, .test, .add, .explain] {
            let items = TaskInstructionCatalog.instructions(for: intent, message: "запрос")
            #expect(!items.isEmpty, "интент \(intent) должен давать инструкции")
            #expect(items.count <= TaskInstructionCatalog.maxInstructions)
            #expect(Set(items).count == items.count, "без дублей")
        }
    }

    @Test("Рефакторинг требует пройти по связям и убрать мёртвый код")
    func refactorInstructionsMentionDependents() {
        let items = TaskInstructionCatalog.instructions(for: .refactor, message: "переделай")
        let joined = items.joined(separator: " ")
        #expect(joined.contains("потребител"), "должен требовать обновить потребителей")
        #expect(joined.contains("мёртв"), "должен требовать удалить мёртвый код")
    }

    @Test("Фикс требует root-cause и теста")
    func fixInstructionsRequireRootCause() {
        let joined = TaskInstructionCatalog.instructions(for: .fix, message: "исправь")
            .joined(separator: " ")
        #expect(joined.contains("корень") || joined.contains("root"))
        #expect(joined.contains("тест"))
    }

    @Test("Ключевые слова запроса добавляют предметные инструкции")
    func keywordExtras() {
        let withBrowser = TaskInstructionCatalog.instructions(
            for: .add, message: "добавь проверку страницы через браузер")
        #expect(withBrowser.contains { $0.contains("browser_fetch") })

        let withUI = TaskInstructionCatalog.instructions(
            for: .refactor, message: "переделай хранение кадров из файлов в память")
        #expect(withUI.contains { $0.contains("UI") || $0.contains("интерфейс") },
                "смена хранилища должна требовать проверить UI-разделы")
    }

    @Test("Неизвестный интент — честно пусто, выдумывать нельзя")
    func unknownIntentIsEmpty() {
        #expect(TaskInstructionCatalog.intent(for: "…") == .other)
        #expect(TaskInstructionCatalog.instructions(for: .other, message: "…").isEmpty)
    }

    @Test("Пакет без внутренней модели всё равно получает инструкции задачи")
    func compilerFallsBackToCatalog() throws {
        // message with a clear refactor intent; localPlan nil = внутренняя
        // модель не назначена (честный fallback-путь владельца).
        let record = FileIndexRecord(
            path: "Sources/FrameStore.swift", hash: "h1", size: 300,
            lastModified: 1, language: "swift",
            searchableText: "final class FrameStore { func save() {} }"
        )
        let board = ContextBoardBuilder.build(projectPath: "/tmp/demo", records: [record])
        let pack = TurnContextCompiler.compile(
            message: "переделай хранилище кадров: файлы → память",
            board: board,
            projectRoot: "/tmp/demo"
        )
        let section = pack.sections.first { $0.title == "Инструкции задачи" }
        let body = try #require(section?.body)
        #expect(body.contains("каталог"), "источник должен быть помечен")
        #expect(body.contains("потребител") || body.contains("мёртв"))
    }

    @Test("Инструкции внутренней модели сильнее каталога")
    func modelInstructionsWin() throws {
        let record = FileIndexRecord(
            path: "Sources/FrameStore.swift", hash: "h1", size: 300,
            lastModified: 1, language: "swift",
            searchableText: "final class FrameStore { func save() {} }"
        )
        let board = ContextBoardBuilder.build(projectPath: "/tmp/demo", records: [record])
        let planResult = LocalQueryPlanResult(
            plan: LocalQueryPlan(
                intent: .refactor, terms: ["framestore"], symbols: ["FrameStore"],
                files: [], memoryTags: [],
                instructions: ["моя внутренняя инструкция"]
            ),
            status: .local(model: "internal-model"),
            dropped: []
        )
        let pack = TurnContextCompiler.compile(
            message: "переделай хранилище",
            board: board,
            projectRoot: "/tmp/demo",
            localPlan: planResult
        )
        let body = pack.sections.first { $0.title == "Инструкции задачи" }?.body
        #expect(try #require(body).contains("внутренней модели"))
        #expect(try #require(body).contains("моя внутренняя инструкция"))
    }
}
