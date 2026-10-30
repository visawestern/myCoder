import Testing
import Foundation
@testable import myCoder

/// Человекочитаемая сводка подготовки контекста: всегда есть что показать
/// в окне «Контекст» — либо собранный пакет, либо честная причина.
@Suite("Сводка контекста (SendContextPreparationLogic.summary)")
struct SendContextSummaryTests {

    @Test("Первый промпт: причина без пакета")
    func firstTurnSummary() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/proj",
            isEnabled: true,
            priorTurns: []
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(summary.contains("Первый промпт"))
        #expect(!summary.isEmpty)
    }

    @Test("Чат без проекта: причина и собранный пакет")
    func chatContextSummary() {
        let turns = [
            ChatHistoryBuilder.Turn(role: "user", content: "вопрос", isFinished: true),
            ChatHistoryBuilder.Turn(role: "assistant", content: "ответ", isFinished: true)
        ]
        let preparation = SendContextPreparationLogic.prepare(
            message: "ещё",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: turns
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(preparation.status == .chatContext)
        #expect(summary.contains("истории чата"))
    }

    @Test("Собранный пакет: сводка называет факты")
    func compiledSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("summ-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "import Foundation\nfinal class UserStore { func load(id: String) -> Int { 0 } }"
        try source.write(to: root.appendingPathComponent("UserStore.swift"), atomically: true, encoding: .utf8)
        let records = [FileIndexRecord(path: "UserStore.swift", hash: "h", size: source.utf8.count,
                                      lastModified: 1_700_000_000, language: "swift", searchableText: source)]

        let preparation = SendContextPreparationLogic.prepare(
            message: "как работает UserStore.load",
            records: records,
            projectPath: root.path,
            isEnabled: true,
            priorTurns: [ChatHistoryBuilder.Turn(role: "user", content: "предыдущий", isFinished: true)]
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(preparation.status == .compiled)
        #expect(summary.contains("Собран точечный контекст"))
    }

    @Test("Нет соответствий: исходный запрос")
    func noEvidenceSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("summ2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "import Foundation\nfinal class UserStore {}"
        try source.write(to: root.appendingPathComponent("UserStore.swift"), atomically: true, encoding: .utf8)
        let records = [FileIndexRecord(path: "UserStore.swift", hash: "h", size: source.utf8.count,
                                      lastModified: 1_700_000_000, language: "swift", searchableText: source)]
        let preparation = SendContextPreparationLogic.prepare(
            message: "совершенно посторонний текст",
            records: records,
            projectPath: root.path,
            isEnabled: true,
            priorTurns: [ChatHistoryBuilder.Turn(role: "user", content: "x", isFinished: true)]
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(preparation.status == .noEvidence)
        #expect(summary.contains("Не найдено соответствий"))
    }

    @Test("Выключен: причина")
    func disabledSummary() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/proj",
            isEnabled: false
        )
        #expect(SendContextPreparationLogic.summary(preparation).contains("выключен"))
    }
}
