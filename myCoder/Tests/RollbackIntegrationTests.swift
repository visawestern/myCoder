import Testing
import Foundation
@testable import myCoder

/// Сборка контекста отката из реальных сообщений, архив удаляемых
/// сообщений в корзину и оркестрация полного цикла отката.
@Suite("Откат — контекст, архив, координатор")
struct RollbackIntegrationTests {

    // MARK: - Сборка контекста

    private func makeMessage(id: String, role: MessageRole, content: String,
                             tools: [String] = [], at date: Date = Date(timeIntervalSince1970: 1000)) -> Message {
        let parts = tools.map { MessagePartContent.toolCall(name: $0, args: "{}", result: nil, callID: nil) }
        return Message(id: id, role: role, content: content, parts: parts)
    }

    @Test("Сборка контекста: рефы, необратимые тулы, последний запрос")
    func buildContextFromMessages() {
        let messages = [
            makeMessage(id: "q1", role: .user, content: "первый запрос"),
            makeMessage(id: "a1", role: .assistant, content: "ответ", tools: ["grep"]),
            makeMessage(id: "q2", role: .user, content: "второй запрос"),
            makeMessage(id: "a2", role: .assistant, content: "ответ", tools: ["run_command", "edit_file"]),
        ]
        let input = RollbackContextBuilder.build(from: messages)
        #expect(input.messages.count == 4)
        #expect(input.messages.map(\.id) == ["q1", "a1", "q2", "a2"])
        // run_command — необратим; grep/edit_file — нет.
        #expect(input.irreversibleActions.count == 1)
        #expect(input.irreversibleActions[0].toolName == "run_command")
        #expect(input.irreversibleActions[0].messageID == "a2")
        #expect(input.lastUserText == "второй запрос")
    }

    @Test("Сборка без user-сообщений → lastUserText nil")
    func buildWithoutUserText() {
        let messages = [makeMessage(id: "a1", role: .assistant, content: "ответ")]
        let input = RollbackContextBuilder.build(from: messages)
        #expect(input.lastUserText == nil)
        #expect(input.irreversibleActions.isEmpty)
    }

    // MARK: - Архив удаляемых сообщений

    @Test("Архив сохраняет дамп удаляемых сообщений в корзину")
    func archiveMessagesToTrash() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let messages = [makeMessage(id: "m1", role: .user, content: "текст")]
        let url = try RollbackChatArchive.archive(messages: messages, sessionID: "s1", homeDirectory: home)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.path.contains("rollback-chats"))
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(obj?.count == 1)
        #expect(obj?[0]["id"] as? String == "m1")
    }

    // MARK: - Координатор

    private final class FakeRestorer: RollbackSnapshotRestoring {
        var restored: [String] = []
        func restoreFromSnapshot(snapshotId: String) throws { restored.append(snapshotId) }
    }
    private final class FakeTrash: RollbackTrashStoring {
        func storeCopy(ofFileAt path: String, scope: String) throws -> String? { path + ".trash" }
    }
    private final class FakeMarkers: RollbackUndoMarking {
        var marked: [String] = []
        func markUndoEntryUsed(id: String) throws { marked.append(id) }
    }

    private func context(target: String, messages: [RollbackMessageRef],
                         entries: [RollbackUndoEntryRef], actions: [IrreversibleAgentAction]) -> RollbackCoordinatorContext {
        RollbackCoordinatorContext(
            targetMessageID: target, messages: messages, undoEntries: entries,
            irreversibleActions: actions,
            snapshotRestoring: FakeRestorer(), trashStoring: FakeTrash(), undoMarking: FakeMarkers())
    }

    @Test("Координатор: полный откат без аудитора → чип full")
    func coordinatorFullWithoutAuditor() async {
        let messages = [RollbackMessageRef(id: "q1", createdAt: 1, role: "user", content: "вопрос"),
                        RollbackMessageRef(id: "a1", createdAt: 2, role: "assistant", content: "ответ")]
        let entries = [RollbackUndoEntryRef(id: "u1", path: "src/a.swift", snapshotID: "s1",
                                            actionType: "edit_file", canUndo: true, createdAt: 1.5)]
        let chip = await RollbackCoordinator.run(context: context(target: "q1", messages: messages, entries: entries, actions: []))
        #expect(chip.full)
        #expect(chip.summary.contains("1"))
        #expect(chip.report.diffs.count == 1)
    }

    @Test("Координатор: аудитор доступен → стадия аудитора в отчёте")
    func coordinatorRecordsAuditorStage() async {
        let messages = [RollbackMessageRef(id: "q1", createdAt: 1, role: "user", content: "вопрос"),
                        RollbackMessageRef(id: "a1", createdAt: 2, role: "assistant", content: "ответ")]
        let chip = await RollbackCoordinator.run(
            context: context(target: "q1", messages: messages, entries: [], actions: [IrreversibleAgentAction(messageID: "a1", toolName: "run_command")]),
            auditor: { _, _ in #"{"canRollback": false, "irreversible": ["run_command"], "stopAtMessageID": "a1"}"# }
        )
        #expect(!chip.full)
        #expect(chip.report.stages.contains { $0.title.contains("Аудитор") })
    }

    @Test("Координатор: аудитор упал → детерминированный план без потери")
    func coordinatorFallsBackWhenAuditorFails() async {
        let messages = [RollbackMessageRef(id: "q1", createdAt: 1, role: "user", content: "вопрос"),
                        RollbackMessageRef(id: "a1", createdAt: 2, role: "assistant", content: "ответ")]
        let chip = await RollbackCoordinator.run(
            context: context(target: "q1", messages: messages, entries: [], actions: []),
            auditor: { _, _ in throw NSError(domain: "test", code: 1) }
        )
        #expect(chip.full)
        #expect(chip.report.stages.contains { $0.title.contains("Аудитор") })
    }
}
