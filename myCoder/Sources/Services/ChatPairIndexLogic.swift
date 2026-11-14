import Foundation

/// Нумерация «пар» в фиде сообщений. Пара — вопрос пользователя и все
/// ответы до следующего вопроса. Каждой строке чата ставится номер пары:
/// у вопроса и его ответов он общий, поэтому кэш отрендеренных сообщений
/// может группировать строки в пары ровно так, как их считает пользователь.
enum ChatPairIndexLogic {
    /// Построить словарь «messageID → номер пары».
    ///
    /// Вход: `messages` — сообщения фида в порядке отображения.
    /// Выход: словарь номеров пар; у сообщений до первого вопроса номер 0.
    /// Зависимости: нет (чистая функция).
    static func pairIndices(for messages: [Message]) -> [String: Int] {
        guard !messages.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        var pair = -1
        for message in messages {
            if message.role == .user {
                pair += 1
            }
            result[message.id] = max(pair, 0)
        }
        return result
    }
}
