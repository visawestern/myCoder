import Foundation
import Testing
@testable import myCoder

/// Нумерация «пар» в фиде сообщений: пара — это вопрос пользователя и
/// все ответы до следующего вопроса. Каждая строка чата получает номер
/// пары (у вопроса и его ответов он общий).
@Suite("Логика нумерации пар сообщений (ChatPairIndexLogic)")
struct ChatPairIndexLogicTests {

    private func m(_ id: String, role: MessageRole) -> Message {
        Message(id: id, role: role, content: id)
    }

    @Test("У user-сообщений и их ответов один номер пары")
    func userAndAnswersSharePair() {
        let messages = [
            m("u1", role: .user),
            m("a1", role: .assistant),
            m("a2", role: .assistant),
            m("u2", role: .user),
            m("a3", role: .assistant),
        ]
        let index = ChatPairIndexLogic.pairIndices(for: messages)
        #expect(index["u1"] == 0)
        #expect(index["a1"] == 0)
        #expect(index["a2"] == 0)
        #expect(index["u2"] == 1)
        #expect(index["a3"] == 1)
    }

    @Test("Первый ответ без предшествующего вопроса получает пару 0")
    func assistantFirstGetsPairZero() {
        let messages = [
            m("a0", role: .assistant),
            m("u1", role: .user),
            m("a1", role: .assistant),
        ]
        let index = ChatPairIndexLogic.pairIndices(for: messages)
        #expect(index["a0"] == 0)
        #expect(index["u1"] == 0)
        #expect(index["a1"] == 0)
    }

    @Test("Системные сообщения не создают новых пар")
    func systemMessagesDoNotCreatePairs() {
        let messages = [
            m("s", role: .system),
            m("u1", role: .user),
            m("a1", role: .assistant),
        ]
        let index = ChatPairIndexLogic.pairIndices(for: messages)
        #expect(index["s"] == 0)
        #expect(index["u1"] == 0)
        #expect(index["a1"] == 0)
    }

    @Test("Пустой фид даёт пустой словарь")
    func emptyFeed() {
        #expect(ChatPairIndexLogic.pairIndices(for: []).isEmpty)
    }
}
