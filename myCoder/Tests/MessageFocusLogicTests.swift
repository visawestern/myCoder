import Foundation
import Testing
@testable import myCoder

/// Tapping a tool-approval notification must land on the message that raised
/// it, not merely open the chat at the newest message (user report
/// 2026-10-29).
@Suite("Переход по уведомлению к сообщению с вызовом тула")
struct MessageFocusLogicTests {

    @Test("Запрос применяется только к своему чату")
    func appliesOnlyToOwnSession() {
        let request = MessageFocusRequest(sessionID: "s1", messageID: "m1")
        #expect(MessageFocusLogic.applies(request, to: "s1"))
        #expect(!MessageFocusLogic.applies(request, to: "s2"))
        #expect(!MessageFocusLogic.applies(nil, to: "s1"))
        #expect(!MessageFocusLogic.applies(request, to: nil))
    }

    @Test("Повторный тап по тому же уведомлению даёт новый токен")
    func repeatedTapGetsFreshToken() {
        let first = MessageFocusRequest(sessionID: "s1", messageID: "m1")
        let second = MessageFocusRequest(sessionID: "s1", messageID: "m1")
        #expect(first.sessionID == second.sessionID)
        #expect(first.messageID == second.messageID)
        #expect(first.token != second.token)
    }

    @Test("Цель считается найденной по id сообщения")
    func findsLoadedMessage() {
        let messages = [
            Message(id: "m1", role: .user, content: "hi"),
            Message(id: "m2", role: .assistant, content: "hello")
        ]
        #expect(MessageFocusLogic.isLoaded(messageID: "m2", in: messages))
        #expect(!MessageFocusLogic.isLoaded(messageID: "m3", in: messages))
    }

    @Test("Старые страницы грузятся только пока цель не найдена и история есть")
    func loadsOlderPagesOnlyWhileNeeded() {
        let loaded = [Message(id: "m1", role: .assistant, content: "x")]
        #expect(MessageFocusLogic.shouldLoadOlderPage(
            messageID: "m9", messages: loaded, hasMoreMessages: true, attempts: 0
        ))
        #expect(!MessageFocusLogic.shouldLoadOlderPage(
            messageID: "m9", messages: loaded, hasMoreMessages: false, attempts: 0
        ))
        #expect(!MessageFocusLogic.shouldLoadOlderPage(
            messageID: "m1", messages: loaded, hasMoreMessages: true, attempts: 0
        ))
        #expect(!MessageFocusLogic.shouldLoadOlderPage(
            messageID: "m9", messages: loaded, hasMoreMessages: true,
            attempts: MessageFocusLogic.maxOlderPageLoads
        ))
    }

    @Test("Уведомление с якорем закрывает панель только при найденном чате")
    func anchoredActionDismissesWithSession() {
        let action = NotificationAction.openMessage(sessionID: "s1", messageID: "m1")
        #expect(NotificationActionRoutingLogic.shouldDismissSheet(after: action, sessionWasFound: true))
        #expect(!NotificationActionRoutingLogic.shouldDismissSheet(after: action, sessionWasFound: false))
    }
}
