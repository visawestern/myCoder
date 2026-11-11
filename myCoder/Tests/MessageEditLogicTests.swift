import Testing
@testable import myCoder

@MainActor
@Suite("Message edit and resend")
struct MessageEditLogicTests {

    @Test("Draft includes text and image parts without duplication")
    func draftFromUserMessage() {
        let message = Message(
            role: .user,
            content: "look",
            parts: [
                .text("look"),
                .image(base64: "abc", mimeType: "image/png")
            ]
        )
        let draft = MessageEditLogic.draft(from: message)
        #expect(draft.text == "look")
        #expect(draft.images.count == 1)
        #expect(draft.images[0].base64 == "abc")
    }

    @Test("Assistant message can be edited but resend uses retry path")
    func canEditAssistant() {
        let message = Message(role: .assistant, content: "hello", isStreaming: false)
        #expect(MessageEditLogic.canEdit(message))
        #expect(MessageEditLogic.canResend(message))
    }

    @Test("Streaming messages cannot be edited")
    func cannotEditStreaming() {
        let message = Message(role: .user, content: "wait", isStreaming: true)
        #expect(!MessageEditLogic.canEdit(message))
    }

    @Test("Empty message shell does not render an orphan action bar")
    func hidesActionsForEmptyShell() {
        #expect(
            !MessageEditLogic.shouldShowActions(
                hasToolCalls: false,
                isStreaming: false,
                canEdit: true,
                displayText: ""
            )
        )
    }

    @Test("Visible finished message keeps its action bar")
    func showsActionsForVisibleMessage() {
        #expect(
            MessageEditLogic.shouldShowActions(
                hasToolCalls: false,
                isStreaming: false,
                canEdit: true,
                displayText: "✨ Ready"
            )
        )
    }

    /// Живой дефект 2026-11-08: у ответа с действиями (tool calls) панель
    /// кнопок скрывалась, поэтому под полученным сообщением не было ни
    /// «Копировать», ни «Сырой ответ». Кнопки должны быть под ЛЮБЫМ
    /// законченным ответом с текстом.
    @Test("Ответ с инструментами тоже показывает кнопки под сообщением")
    func showsActionsForAssistantMessageWithToolCalls() {
        #expect(
            MessageEditLogic.shouldShowActions(
                hasToolCalls: true,
                isStreaming: false,
                canEdit: false,
                displayText: "Готово: план из 3 шагов"
            )
        )
    }

    /// Во время стриминга панель по-прежнему не показывается: ответ ещё
    /// меняется, кнопка сырого ответа неполна.
    @Test("Стриминговый ответ не показывает кнопки до завершения")
    func hidesActionsWhileStreaming() {
        #expect(
            !MessageEditLogic.shouldShowActions(
                hasToolCalls: true,
                isStreaming: true,
                canEdit: false,
                displayText: "Частичный ответ"
            )
        )
    }
}
