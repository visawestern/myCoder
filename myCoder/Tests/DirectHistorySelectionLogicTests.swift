import Testing
import Foundation
@testable import myCoder

/// Root cause of the "3D aquarium lost context" bug (live 2026-11-12):
/// the direct OpenAI path cut history with `dropLast(2)`. When a warning
/// notice was appended before the assistant placeholder, the cut removed a
/// REAL assistant answer (the turn that created `aquarium_3d.html`). The
/// model then no longer saw the file and re-searched for it.
///
/// The fix is a pure selection rule: history is everything strictly BEFORE
/// the user message that started the current turn. Not "last two messages".
@MainActor
@Suite("История до текущего хода — выбор по последнему user-сообщению")
struct DirectHistorySelectionLogicTests {

    private func message(_ id: String, _ role: MessageRole, _ content: String) -> Message {
        Message(id: id, role: role, content: content, isFinished: true)
    }

    @Test("Берёт всё до текущего user-сообщения, а не последние два")
    func keepsEverythingBeforeCurrentUserMessage() {
        let messages = [
            message("u1", .user, "сделай аквариум"),
            message("a1", .assistant, "создал aquarium_3d.html"),
            message("u2", .user, "запусти его"),
            message("a2", .assistant, ""),
        ]
        let prior = DirectHistorySelectionLogic.priorTurns(from: messages, currentUserMessageID: "u2")
        #expect(prior.map(\.id) == ["u1", "a1"],
                "фактически: \(prior.map(\.id)) — ожидалось сохранение ответа a1")
    }

    @Test("Предупреждение после текущего user-сообщения не сдвигает границу")
    func warningNoticeDoesNotShiftBoundary() {
        // Exactly the production order: user bubble, warning notice, placeholder.
        let messages = [
            message("u1", .user, "сделай аквариум"),
            message("a1", .assistant, "создал aquarium_3d.html"),
            message("u2", .user, "запусти его"),
            message("w2", .system, "⚠️ Память проекта не прочитана"),
            message("a2", .assistant, ""),
        ]
        let prior = DirectHistorySelectionLogic.priorTurns(from: messages, currentUserMessageID: "u2")
        #expect(prior.map(\.id) == ["u1", "a1"],
                "фактически: \(prior.map(\.id)) — ожидалось u1, a1")
    }

    @Test("Без id текущего сообщения границей служит последний user")
    func fallsBackToLastUserMessage() {
        let messages = [
            message("u1", .user, "q1"),
            message("a1", .assistant, "a1"),
            message("u2", .user, "q2"),
            message("a2", .assistant, ""),
        ]
        let prior = DirectHistorySelectionLogic.priorTurns(from: messages)
        #expect(prior.map(\.id) == ["u1", "a1"])
    }

    @Test("Нет ни одного user-сообщения — истории нет")
    func noUserMessageMeansNoHistory() {
        let messages = [message("s1", .system, "summary"), message("a1", .assistant, "x")]
        let prior = DirectHistorySelectionLogic.priorTurns(from: messages)
        #expect(prior.isEmpty)
    }

    @Test("Системные сообщения и предупреждения не попадают в историю модели")
    func systemAndWarningMessagesAreExcluded() {
        let messages = [
            message("s1", .system, "[Conversation summary]\nкратко"),
            message("w1", .system, "⚠️ Память проекта не прочитана"),
            message("u1", .user, "q1"),
            message("a1", .assistant, "a1"),
            message("u2", .user, "q2"),
        ]
        let prior = DirectHistorySelectionLogic.priorTurns(from: messages, currentUserMessageID: "u2")
        #expect(prior.map(\.id) == ["u1", "a1"],
                "фактически: \(prior.map(\.id)) — system/notice не должны попадать в модель")
    }
}

/// Warning notices used to be persisted as ASSISTANT messages. They then
/// counted as real turns in `ChatHistoryBuilder` and pushed the aquarium turn
/// out of the 20-message window. New notices are `.system`; the builder also
/// ignores legacy assistant rows that start with the warning glyph.
@MainActor
@Suite("Предупреждения хода — системная роль и фильтр истории")
struct TurnNoticeBuilderTests {

    @Test("Новое предупреждение сохраняется как system, а не assistant")
    func warningNoticeIsSystemRole() {
        let notice = TurnNoticeBuilder.warningNotice("Память проекта не прочитана")
        #expect(notice.role == .system,
                "фактически: \(notice.role) — ожидалось .system")
        #expect(notice.content == "⚠️ Память проекта не прочитана")
        #expect(notice.isFinished)
    }

    @Test("Старое предупреждение с ролью assistant не попадает в историю")
    func legacyAssistantNoticeIsDropped() {
        let history = ChatHistoryBuilder.history(from: [
            ChatHistoryBuilder.Turn(role: "user", content: "q1", isFinished: true),
            ChatHistoryBuilder.Turn(role: "assistant", content: "⚠️ Память проекта не прочитана", isFinished: true),
            ChatHistoryBuilder.Turn(role: "assistant", content: "a1", isFinished: true),
            ChatHistoryBuilder.Turn(role: "user", content: "q2", isFinished: true),
        ])
        #expect(history.map(\.content) == ["q1", "a1", "q2"],
                "фактически: \(history.map(\.content)) — ожидалось без предупреждения")
    }
}
