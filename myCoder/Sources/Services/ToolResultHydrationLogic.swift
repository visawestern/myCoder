import Foundation

/// Чистая логика гидрации сообщений результатами тулов: после lite-
/// загрузки истории часть результатов уже лежит в `ToolResultStore`
/// (RAM), остальные нужно один раз запросить из БД и подмешать в части
/// сообщений. Логика не зависит от БД и UI.
enum ToolResultHydrationLogic {
    /// Собрать callID, которые нужно запросить с диска: только те, чьих
    /// значений ещё нет в памяти. Ключи, уже лежащие в `memory`, не
    /// должны попадать в запрос к БД (memory-first).
    ///
    /// Вход: `keys` — все нужные ключи; `memory` — RAM-хранилище.
    /// Выход: `fromMemory` — известные из памяти пары;
    /// `missing` — ключи, которые нужно качать.
    /// Зависимости: нет (чистая функция).
    static func splitKeys(
        _ keys: [String],
        memory: [String: String]
    ) -> (fromMemory: [String: String], missing: [String]) {
        var known: [String: String] = [:]
        var missing: [String] = []
        for key in keys {
            if let value = memory[key] {
                known[key] = value
            } else {
                missing.append(key)
            }
        }
        return (known, missing)
    }

    /// Собрать ключи, которые нужно запросить, из сообщений: callID
    /// тулов, у которых результат отсутствует в памяти (`result == nil`),
    /// но существует в хранилище (`hasStoredResult`).
    ///
    /// Вход: `messages` — сообщения (lite-загруженные).
    /// Выход: упорядоченный массив callID.
    /// Зависимости: нет (чистая функция).
    static func keysNeeded(messages: [Message]) -> [String] {
        var keys: [String] = []
        for message in messages {
            for part in message.parts {
                guard case .toolCall(_, _, let result, let callID) = part,
                      result == nil,
                      let callID,
                      !callID.isEmpty,
                      let meta = message.toolResultMeta[callID],
                      meta.hasStoredResult else { continue }
                keys.append(callID)
            }
        }
        return keys
    }

    /// Применить найденные результаты к сообщениям: заменяет части
    /// `.toolCall` с `result == nil` на части с текстом результата.
    /// Части с уже загруженным результатом не трогаются; сообщения без
    /// изменений возвращаются как есть.
    ///
    /// Вход: `results` — словарь «callID → текст результата»;
    /// `messages` — исходные сообщения.
    /// Выход: новые сообщения с заполненными результатами.
    /// Зависимости: нет (чистая функция).
    static func apply(
        results: [String: String],
        to messages: [Message]
    ) -> [Message] {
        messages.map { message in
            var copy = message
            var changed = false
            copy.parts = message.parts.map { part -> MessagePartContent in
                guard case .toolCall(let name, let args, let result, let callID) = part,
                      result == nil,
                      let callID,
                      let value = results[callID] else { return part }
                changed = true
                return .toolCall(name: name, args: args, result: value, callID: callID)
            }
            return changed ? copy : message
        }
    }
}
