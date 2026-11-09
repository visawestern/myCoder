import Foundation

/// Сборка промпта для внутренней модели-аудитора отката и парсинг её
/// вердикта. Модель получает диалог и вызовы инструментов, произошедшие
/// после целевого запроса, и сообщает, что можно откатить, а что нет.
enum RollbackPromptBuilder {

    /// Системная инструкция аудитора.
    static func systemPrompt() -> String {
        """
        Ты — аудитор безопасного отката диалога. Тебе покажут диалог чата и \
        вызовы инструментов, произошедшие после целевого запроса. Определи, \
        какие изменения можно откатить, а какие — необратимы (запущенные \
        команды, внешние эффекты, потерянные данные). Верни ТОЛЬКО JSON: \
        {"canRollback": true|false, "irreversible": ["инструмент", ...], \
        "stopAtMessageID": "id_сообщения_или_null"}
        """
    }

    /// Пользовательская часть: диалог + вызовы инструментов.
    static func userPrompt(
        targetMessageID: String,
        messages: [RollbackMessageRef],
        irreversibleActions: [IrreversibleAgentAction]
    ) -> String {
        var lines: [String] = []
        lines.append("Целевой запрос: \(targetMessageID)")
        lines.append("")
        lines.append("Диалог (от начала до конца):")
        lines.append("")
        for m in messages {
            let role = m.role == "user" ? "Пользователь" : "Ассистент"
            lines.append("[\(m.id)] \(role): \(m.content)")
        }
        lines.append("")
        lines.append("Вызовы инструментов после целевого запроса:")
        if irreversibleActions.isEmpty {
            lines.append("(нет)")
        } else {
            for action in irreversibleActions {
                lines.append("- \(action.toolName) (после \(action.messageID))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Распарсить вердикт аудитора. nil — если ответ не JSON или нет ключа
    /// `canRollback` (тогда вызывающий код использует детерминированный план).
    static func parseVerdict(_ json: String) -> RollbackVerdict? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let canRollback = obj["canRollback"] as? Bool else {
            return nil
        }
        let irreversible = (obj["irreversible"] as? [String]) ?? []
        let stopAt = obj["stopAtMessageID"] as? String
        return RollbackVerdict(
            canRollback: canRollback,
            irreversible: irreversible,
            stopAtMessageID: stopAt,
            valid: true
        )
    }
}
