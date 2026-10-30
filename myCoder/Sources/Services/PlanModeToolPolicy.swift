import Foundation

/// Политика тулов в режиме «План».
///
/// План — режим только для чтения: запросы на безопасность/одобрения
/// (промпты пользователю) показывать НЕ нужно (директива 2026-10-30).
/// Мутирующие тулы (write_file/edit_file/patch и т.п.) отклоняются без
/// вопроса — модели возвращается текст-отказ, как в opencode plan-агенте
/// (права edit/write/patch запрещены). Остальные тулы выполняются как
/// обычно.
enum PlanModeToolPolicy {

    enum Decision: Equatable {
        case execute
        case deny(reason: String)
    }

    /// Видимое объяснение отказа для модели.
    static let deniedReason =
        "Plan mode is read-only: this tool call was not executed. Switch to build mode to make changes."

    static func decision(for call: WebToolCall, isPlanMode: Bool) -> Decision {
        guard isPlanMode else { return .execute }
        switch call.name.lowercased() {
        case "write_file", "edit_file", "patch", "write", "edit", "rename_file":
            return .deny(reason: deniedReason)
        default:
            return .execute
        }
    }
}
