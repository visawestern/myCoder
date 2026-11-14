import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Ленивая загрузка результатов тулов

    /// Прочитать части сообщения БЕЗ текстов результатов тулов: вместо
    /// `tool_result` приходят флаг наличия и длина. Используется при
    /// загрузке истории чата — спойлеры открывают результаты лениво,
    /// одним запросом, а не тащат все выды при открытии чата.
    ///
    /// Вход: `messageId` — id сообщения.
    /// Выход: записи частей в порядке `sequence_order` с метаданными
    /// результата вместо текста.
    /// Зависимости: SQLite, `SQLiteSafeQuery`.
    func getMessagePartsLite(messageId: String) throws -> [MessagePartRecordLite] {
        guard let db = db else { throw DatabaseError.notInitialized }
        let sql = """
            SELECT id, message_id, type, content, tool_name, tool_args,
                   tool_call_id, sequence_order,
                   (tool_result IS NOT NULL) AS has_tool_result,
                   COALESCE(LENGTH(tool_result), 0) AS tool_result_length
            FROM message_parts
            WHERE message_id = ?
            ORDER BY sequence_order ASC
        """
        let rows = try SQLiteSafeQuery.rows(db.prepare(sql, [messageId]))
        return rows.compactMap { row in
            guard let id = row[0] as? String else { return nil }
            return MessagePartRecordLite(
                id: id,
                messageId: (row[1] as? String) ?? "",
                type: (row[2] as? String) ?? "",
                content: row[3] as? String,
                toolName: row[4] as? String,
                toolArgs: row[5] as? String,
                toolCallId: row[6] as? String,
                sequenceOrder: (row[7] as? Int64).map(Int.init) ?? 0,
                hasToolResult: (row[8] as? Int64) == 1,
                toolResultLength: (row[9] as? Int64).map(Int.init) ?? 0
            )
        }
    }

    /// Пакетно достать тексты результатов тулов по callID — ОДНИМ
    /// запросом (без N+1). Возвращает только те записи, у которых текст
    /// результата существует (включая пустую строку).
    ///
    /// Вход: `callIDs` — массив ключей (не должен быть пустым для
    /// запроса; пустой список возвращает пустой словарь).
    /// Выход: словарь «callID → текст результата».
    /// Зависимости: SQLite, `SQLiteSafeQuery`.
    func getToolResults(callIDs: [String]) throws -> [String: String] {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard !callIDs.isEmpty else { return [:] }
        let unique = Array(Set(callIDs))
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ", ")
        let sql = """
            SELECT tool_call_id, tool_result
            FROM message_parts
            WHERE tool_call_id IN (\(placeholders)) AND tool_result IS NOT NULL
        """
        var results: [String: String] = [:]
        for row in try SQLiteSafeQuery.rows(db.prepare(sql, unique)) {
            if let key = row[0] as? String, let value = row[1] as? String {
                results[key] = value
            }
        }
        return results
    }
}
