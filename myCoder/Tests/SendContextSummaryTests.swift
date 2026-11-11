import Testing
import Foundation
@testable import myCoder

/// Человекочитаемая сводка подготовки контекста: всегда есть что показать
/// в окне «Контекст» — либо собранный пакет, либо честная причина.
@MainActor
@Suite("Сводка контекста (SendContextPreparationLogic.summary)")
struct SendContextSummaryTests {

    @Test("Первый промпт в чате без проекта: причина без пакета")
    func firstTurnSummary() {
        // An OPEN project supplies evidence even before the first chat turn
        // (user directive 2026-11-03), so "first turn" now means a chat with
        // no project AND no history — there is genuinely nothing to collect.
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: []
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(summary.contains("Первый промпт"))
        #expect(!summary.isEmpty)
    }

    @Test("Открытый проект без индекса: честная причина, а не «первый промпт»")
    func openProjectWithoutIndexIsNoEvidence() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/proj",
            isEnabled: true,
            priorTurns: []
        )
        let summary = SendContextPreparationLogic.summary(preparation)
        #expect(!summary.contains("Первый промпт"))
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
        #expect(summary.contains("Совпадений в коде не найдено"))
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
