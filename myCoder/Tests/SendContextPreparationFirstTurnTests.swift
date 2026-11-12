import Testing
import Foundation
@testable import myCoder

/// Правила сборки контекста (директивы пользователя 2026-10-30):
/// 3) первый промпт в чате — контекст не собирается «из ничего»;
/// 4) открыт проект: первый промпт тоже без контекста, далее контекст =
///    изученные данные + история самого чата;
/// 5) чат без проекта: контекст = все предыдущие сообщения чата.
@MainActor
@Suite("Контекст: первый промпт и история чата")
struct SendContextPreparationFirstTurnTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-firstturn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = """
        import Foundation

        final class UserStore {
            func load(id: String) -> Int { 0 }
        }
        """
        try source.write(to: root.appendingPathComponent("UserStore.swift"),
                         atomically: true, encoding: .utf8)
        return root
    }

    private func records(for root: URL) throws -> [FileIndexRecord] {
        let text = try String(contentsOf: root.appendingPathComponent("UserStore.swift"), encoding: .utf8)
        return [FileIndexRecord(path: "UserStore.swift", hash: "h", size: text.utf8.count,
                                lastModified: 1_700_000_000, language: "swift", searchableText: text)]
    }

    private func turns() -> [ChatHistoryBuilder.Turn] {
        [
            ChatHistoryBuilder.Turn(role: "user", content: "первое сообщение", isFinished: true),
            ChatHistoryBuilder.Turn(role: "assistant", content: "первый ответ", isFinished: true)
        ]
    }

    @Test("Первый промпт собирает контекст проекта")
    func firstTurnWithProjectCollectsContext() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "UserStore.load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true,
            priorTurns: []
        )
        #expect(preparation.status == .compiled)
        #expect(preparation.pack?.text.contains("UserStore.swift:") == true)
        #expect(preparation.warning == nil)
        #expect(preparation.modelText.contains("UserStore.load"))
    }

    @Test("Первый промпт в чате без проекта НЕ собирает контекст")
    func firstTurnWithoutProjectDoesNotCollectContext() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: []
        )
        #expect(preparation.status == .projectlessFirstTurn)
        #expect(preparation.pack == nil)
        #expect(preparation.modelText == "привет")
    }

    @Test("Со второго промпта контекст проекта включает историю чата")
    func laterTurnWithProjectIncludesChatHistory() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "второй вопрос про UserStore.load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true,
            priorTurns: turns()
        )
        #expect(preparation.status == .compiled)
        #expect(preparation.pack != nil)
        #expect(preparation.pack?.text.contains("История чата") == true)
        #expect(preparation.pack?.text.contains("первое сообщение") == true)
    }

    @Test("Чат без проекта: предыдущие сообщения становятся контекстом")
    func projectlessLaterTurnUsesChatHistoryAsContext() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "ещё вопрос",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: turns()
        )
        #expect(preparation.status == .chatContext)
        #expect(preparation.pack != nil)
        #expect(preparation.pack?.text.contains("ещё вопрос") == true)
        #expect(preparation.pack?.text.contains("первое сообщение") == true)
        #expect(preparation.modelText == preparation.pack?.text)
    }

    @Test("Выключенный контекст остаётся выключенным и на первом промпте")
    func disabledStaysDisabledOnFirstTurn() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "привет",
            records: [],
            projectPath: "/tmp/project",
            isEnabled: false,
            priorTurns: []
        )
        #expect(preparation.status == .disabled)
        #expect(preparation.modelText == "привет")
    }

    @Test("Режим «План» в чате без проекта не собирает контекст на первом промпте")
    func planModeWithoutProjectStaysSilentOnFirstTurn() {
        let preparation = SendContextPreparationLogic.prepare(
            message: "составь план",
            records: [],
            projectPath: "",
            isEnabled: true,
            priorTurns: [],
            isPlanMode: true
        )
        #expect(preparation.status == .projectlessFirstTurn)
        #expect(preparation.pack == nil)
        #expect(preparation.warning == nil)
        #expect(preparation.modelText == "составь план")
    }

    @Test("Режим «План» собирает контекст даже на первом промпте")
    func planModeCompilesContextOnFirstTurn() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let preparation = SendContextPreparationLogic.prepare(
            message: "составь план для UserStore.load",
            records: try records(for: root),
            projectPath: root.path,
            isEnabled: true,
            priorTurns: [],
            isPlanMode: true
        )
        #expect(preparation.status == .compiled)
        #expect(preparation.pack != nil)
        #expect(preparation.pack?.text.contains("UserStore.swift:") == true)
    }
}
