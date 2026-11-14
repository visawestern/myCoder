import Foundation
import Testing
@testable import myCoder

/// Чистая логика LRU-эвикции кэша отрендеренных сообщений. Единица
/// хранения — ПАРА (вопрос пользователя + ответ). Лимиты: 100 пар на чат,
/// 500 пар суммарно. При переполнении чата вытесняются самые старые пары
/// ЭТОГО чата; при глобальном переполнении — пары самого старого чата.
/// LRU (а не FIFO): обращение к чату делает его «свежим».
@Suite("Логика кэша отрендеренных сообщений (RenderedMessageCacheLogic)")
struct RenderedMessageCacheLogicTests {

    // MARK: - Пер-чатный лимит (100)

    @Test("Свыше 100 пар одного чата вытесняются самые старые пары этого чата")
    func perChatEvictsOldestOfSameChat() {
        var state = RenderedCacheState()
        var allEvicted: [RenderedMessageKey] = []
        for i in 0..<105 {
            var evicted: [RenderedMessageKey] = []
            (state, evicted) = RenderedMessageCacheLogic.insert(
                sessionID: "chat-A", pairIndex: i, state: state
            )
            allEvicted.append(contentsOf: evicted)
        }
        #expect(state.chatPairOrder["chat-A"]?.count == 100)
        // Вытеснены первые 5 пар ровно чата A (0...4), по одной на
        // каждую вставку после сотой.
        let evictedKeys = Set(allEvicted)
        #expect(evictedKeys == Set((0..<5).map { RenderedMessageKey(sessionID: "chat-A", pairIndex: $0) }))
        #expect(allEvicted.count == 5)
        #expect(state.totalPairs == 100)
        #expect(state.chatPairOrder["chat-A"] == Array(5..<105))
    }

    @Test("Повторная вставка существующей пары не растит счётчик")
    func duplicateInsertDoesNotGrow() {
        var state = RenderedCacheState()
        (state, _) = RenderedMessageCacheLogic.insert(sessionID: "A", pairIndex: 0, state: state)
        (state, _) = RenderedMessageCacheLogic.insert(sessionID: "A", pairIndex: 0, state: state)
        #expect(state.totalPairs == 1)
        #expect(state.chatPairOrder["A"] == [0])
    }

    // MARK: - Глобальный лимит (500)

    @Test("Свыше 500 пар выгружается самый старый чат")
    func globalEvictsOldestChat() {
        var state = RenderedCacheState()
        // Шесть чатов по 90 пар = 540 (> 500).
        for chat in ["A", "B", "C", "D", "E", "F"] {
            for i in 0..<90 {
                (state, _) = RenderedMessageCacheLogic.insert(
                    sessionID: chat, pairIndex: i, state: state
                )
            }
        }
        #expect(state.totalPairs == 500)
        // Самый старый чат A: из него вытеснены 40 старейших пар.
        #expect(state.chatPairOrder["A"]?.count == 50)
        #expect(state.chatPairOrder["A"] == Array(40..<90))
        // Остальные чаты не тронуты.
        #expect(state.chatPairOrder["B"]?.count == 90)
        #expect(state.chatPairOrder["F"]?.count == 90)
    }

    @Test("Обращение к чату делает его свежим (LRU)")
    func accessMakesChatFresh() {
        var state = RenderedCacheState()
        // Пять чатов по 90 пар = 450 (в пределах глобального лимита).
        for chat in ["A", "B", "C", "D", "E"] {
            for i in 0..<90 {
                (state, _) = RenderedMessageCacheLogic.insert(
                    sessionID: chat, pairIndex: i, state: state
                )
            }
        }
        #expect(state.totalPairs == 450)
        // Обращаемся к A — теперь он новый (в конце globalAccessOrder).
        state = RenderedMessageCacheLogic.recordAccess(sessionID: "A", state: state)
        #expect(state.globalAccessOrder.last == "A")
        // Шестой чат F добавляет 60 пар: суммарно 510 > 500, поэтому
        // глобальная эвикция выгружает 10 старейших пар САМОГО СТАРОГО
        // чата B (LRU), не трогая свежий A.
        for i in 0..<60 {
            (state, _) = RenderedMessageCacheLogic.insert(
                sessionID: "F", pairIndex: i, state: state
            )
        }
        #expect(state.totalPairs == 500)
        #expect(state.chatPairOrder["B"]?.count == 80)
        #expect(state.chatPairOrder["B"] == Array(10..<90))
        #expect(state.chatPairOrder["A"]?.count == 90)
        #expect(state.chatPairOrder["F"]?.count == 60)
    }

    @Test("Глобальный лимит не ломает пер-чатный: один чат не растёт выше 100")
    func globalDoesNotBreakPerChat() {
        var state = RenderedCacheState()
        for i in 0..<200 {
            (state, _) = RenderedMessageCacheLogic.insert(
                sessionID: "only", pairIndex: i, state: state
            )
        }
        #expect(state.chatPairOrder["only"]?.count == 100)
        #expect(state.totalPairs == 100)
        #expect(state.chatPairOrder["only"] == Array(100..<200))
    }

    // MARK: - Удаление чата

    @Test("Удаление чата чистит все его пары и убирает его из порядка доступа")
    func removeChatClearsAllPairs() {
        var state = RenderedCacheState()
        for chat in ["A", "B"] {
            for i in 0..<40 {
                (state, _) = RenderedMessageCacheLogic.insert(
                    sessionID: chat, pairIndex: i, state: state
                )
            }
        }
        let (next, removed) = RenderedMessageCacheLogic.removeChat(sessionID: "A", state: state)
        #expect(removed.count == 40)
        #expect(next.totalPairs == 40)
        #expect(next.chatPairOrder["A"] == nil)
        #expect(!next.globalAccessOrder.contains("A"))
        #expect(next.chatPairOrder["B"]?.count == 40)
    }

    // MARK: - Следующий индекс пары

    @Test("Следующий индекс пары — следующий после максимального в чате")
    func nextPairIndexFollowsMax() {
        let state = RenderedCacheState()
        #expect(RenderedMessageCacheLogic.nextPairIndex(sessionID: "A", state: state) == 0)
        var s = state
        (s, _) = RenderedMessageCacheLogic.insert(sessionID: "A", pairIndex: 3, state: s)
        #expect(RenderedMessageCacheLogic.nextPairIndex(sessionID: "A", state: s) == 4)
    }

    // MARK: - Пустой/крайний случай

    @Test("Вставка в пустой кэш не вытесняет ничего")
    func firstInsertEvictsNothing() {
        let state = RenderedCacheState()
        let (next, evicted) = RenderedMessageCacheLogic.insert(
            sessionID: "A", pairIndex: 0, state: state
        )
        #expect(evicted.isEmpty)
        #expect(next.totalPairs == 1)
        #expect(next.globalAccessOrder == ["A"])
    }
}
