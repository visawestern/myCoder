import Foundation

/// Сборка контекста отката из реальных сообщений чата: плоские рефы для
/// планирования, список необратимых действий (инструменты, изменившие
/// состояние вне файлов) и текст последнего запроса. Чистая функция —
/// без побочных эффектов, покрыта тестами.
enum RollbackContextBuilder {

    /// Инструменты, которые считаются необратимыми при откате: их эффект
    /// нельзя отменить восстановлением файлов из снапшотов.
    static let irreversibleToolNames: Set<String> = ["run_command", "git_push", "git_pull"]

    struct Input: Equatable {
        let messages: [RollbackMessageRef]
        let irreversibleActions: [IrreversibleAgentAction]
        let lastUserText: String?
    }

    static func build(from messages: [Message]) -> Input {
        var refs: [RollbackMessageRef] = []
        var actions: [IrreversibleAgentAction] = []
        var lastUserText: String?

        for message in messages {
            refs.append(RollbackMessageRef(
                id: message.id,
                createdAt: message.timestamp.timeIntervalSince1970,
                role: roleName(message.role),
                content: message.content
            ))
            if message.role == .user {
                lastUserText = message.content
            }
            for part in message.parts {
                if case .toolCall(let name, _, _, _) = part,
                   irreversibleToolNames.contains(name) {
                    actions.append(IrreversibleAgentAction(messageID: message.id, toolName: name))
                }
            }
        }
        return Input(messages: refs, irreversibleActions: actions, lastUserText: lastUserText)
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }
}
