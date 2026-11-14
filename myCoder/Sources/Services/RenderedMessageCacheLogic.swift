import Foundation

/// Ключ записи кэша отрендеренных сообщений: пара (чат, номер пары).
/// Номер пары — позиция пары «вопрос + ответ» в чате (0-based).
struct RenderedMessageKey: Hashable, Sendable {
    let sessionID: String
    let pairIndex: Int
}

/// Неизменяемое состояние кэша отрендеренных сообщений, над которым
/// работают чистые функции `RenderedMessageCacheLogic`. Хранит только
/// индексы и порядок доступа — без самих данных рендера.
struct RenderedCacheState: Equatable, Sendable {
    /// Пары каждого чата в порядке появления (старая → новая).
    var chatPairOrder: [String: [Int]] = [:]
    /// Сессии от самой старой к самой новой по последнему доступу.
    var globalAccessOrder: [String] = []
    /// Общее число пар во всех чатах.
    var totalPairs = 0
}

/// Чистая логика LRU-эвикции кэша отрендеренных сообщений.
/// Лимиты: 100 пар на чат, 500 пар суммарно по всем чатам.
/// Вытеснение: при переполнении чата — самые старые пары ЭТОГО чата;
/// при глобальном переполнении — пары самого старого чата (LRU).
enum RenderedMessageCacheLogic {
    static let perChatLimit = 100
    static let globalLimit = 500

    /// Отметить обращение к чату: он становится самым «свежим».
    ///
    /// Вход: `sessionID`; `state`.
    /// Выход: новое состояние с чатом в конце `globalAccessOrder`.
    /// Зависимости: нет (чистая функция).
    static func recordAccess(sessionID: String, state: RenderedCacheState) -> RenderedCacheState {
        var next = state
        next.globalAccessOrder.removeAll { $0 == sessionID }
        next.globalAccessOrder.append(sessionID)
        return next
    }

    /// Следующий свободный номер пары для чата: максимальный + 1.
    ///
    /// Вход: `sessionID`; `state`.
    /// Выход: номер пары для следующей вставки.
    /// Зависимости: нет (чистая функция).
    static func nextPairIndex(sessionID: String, state: RenderedCacheState) -> Int {
        (state.chatPairOrder[sessionID]?.max() ?? -1) + 1
    }

    /// Вставить пару и выполнить эвикцию по обоим лимитам.
    ///
    /// Вход: `sessionID`; `pairIndex`; `state`.
    /// Выход: новое состояние + список ключей, которые нужно выгрузить
    /// из памяти (старейшие пары чата при 100; пары самого старого чата
    /// при 500).
    /// Зависимости: нет (чистая функция).
    static func insert(
        sessionID: String,
        pairIndex: Int,
        state: RenderedCacheState
    ) -> (state: RenderedCacheState, evicted: [RenderedMessageKey]) {
        var next = state
        var evicted: [RenderedMessageKey] = []

        var pairs = next.chatPairOrder[sessionID] ?? []
        if !pairs.contains(pairIndex) {
            pairs.append(pairIndex)
            next.totalPairs += 1
        }

        // Пер-чатный лимит: вытесняются самые старые пары ЭТОГО чата.
        while pairs.count > perChatLimit, let oldest = pairs.first {
            pairs.removeFirst()
            evicted.append(RenderedMessageKey(sessionID: sessionID, pairIndex: oldest))
            next.totalPairs -= 1
        }
        if pairs.isEmpty {
            next.chatPairOrder[sessionID] = nil
            next.globalAccessOrder.removeAll { $0 == sessionID }
        } else {
            next.chatPairOrder[sessionID] = pairs
            next = recordAccess(sessionID: sessionID, state: next)
        }

        // Глобальный лимит: выгружаются пары самого старого чата (LRU).
        while next.totalPairs > globalLimit,
              let oldestSession = next.globalAccessOrder.first,
              var oldestPairs = next.chatPairOrder[oldestSession] {
            guard let oldest = oldestPairs.first else { break }
            oldestPairs.removeFirst()
            next.totalPairs -= 1
            evicted.append(RenderedMessageKey(sessionID: oldestSession, pairIndex: oldest))
            if oldestPairs.isEmpty {
                next.chatPairOrder[oldestSession] = nil
                next.globalAccessOrder.removeFirst()
            } else {
                next.chatPairOrder[oldestSession] = oldestPairs
            }
        }
        return (next, evicted)
    }

    /// Удалить чат целиком: все его пары освобождаются.
    ///
    /// Вход: `sessionID`; `state`.
    /// Выход: новое состояние + список освобождённых ключей.
    /// Зависимости: нет (чистая функция).
    static func removeChat(
        sessionID: String,
        state: RenderedCacheState
    ) -> (state: RenderedCacheState, removed: [RenderedMessageKey]) {
        var next = state
        var removed: [RenderedMessageKey] = []
        if let pairs = next.chatPairOrder.removeValue(forKey: sessionID) {
            for pair in pairs {
                removed.append(RenderedMessageKey(sessionID: sessionID, pairIndex: pair))
            }
            next.totalPairs -= pairs.count
        }
        next.globalAccessOrder.removeAll { $0 == sessionID }
        return (next, removed)
    }
}
