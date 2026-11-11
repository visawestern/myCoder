import Testing
import Foundation
@testable import myCoder

/// Чистый разбор параметров `chat.rollback` — без AppState/UI.
@MainActor
@Suite("AppActionRouter chat.rollback")
struct AppActionRouterRollbackTests {

    @Test("Разбор валидных параметров")
    func parsesValidParams() throws {
        let request = try AppActionRouter.rollbackRequest(
            params: ["messageId": "msg-1", "chatId": "chat-9"],
            defaultChatID: "default-chat"
        )
        #expect(request.messageID == "msg-1")
        #expect(request.chatID == "chat-9")
    }

    @Test("Без messageId — ошибка missingParameter")
    func missingMessageIDThrows() {
        #expect(throws: AppActionError.self) {
            let _ = try AppActionRouter.rollbackRequest(
                params: ["chatId": "chat-9"],
                defaultChatID: nil
            )
        }
    }

    @Test("Пустой messageId — ошибка")
    func emptyMessageIDThrows() {
        #expect(throws: AppActionError.self) {
            let _ = try AppActionRouter.rollbackRequest(
                params: ["messageId": "  "],
                defaultChatID: nil
            )
        }
    }

    @Test("chatId не задан — берётся defaultChatID")
    func fallsBackToDefaultChatID() throws {
        let request = try AppActionRouter.rollbackRequest(
            params: ["messageId": "msg-1"],
            defaultChatID: "selected-chat"
        )
        #expect(request.chatID == "selected-chat")
    }

    @Test("Пустой chatId — берётся defaultChatID")
    func emptyChatIDFallsBack() throws {
        let request = try AppActionRouter.rollbackRequest(
            params: ["messageId": "msg-1", "chatId": ""],
            defaultChatID: "selected-chat"
        )
        #expect(request.chatID == "selected-chat")
    }
}
