import Foundation

/// Источник сообщений для отката диалога.
///
/// Откат работает с полным срезом диалога. Кнопка в чате всегда использует
/// живой фид `MessageStore` (чат открыт и загружен). API-вызов (`chat.rollback`)
/// может прийти для чата, который не выбран — тогда фид пуст, и сообщения
/// поднимаются из БД через `DatabaseBridge.loadMessages`. Решение, какой
/// источник использовать, вынесено в чистую функцию (покрыта тестами).
enum RollbackDialogueLoader {
    static func resolve(
        for sessionID: String,
        fromStore: () -> [Message],
        fromDatabase: (String) -> [Message]
    ) -> [Message] {
        let live = fromStore()
        if !live.isEmpty { return live }
        return fromDatabase(sessionID)
    }
}
