import Foundation

/// Применение результата отката к чату: урезание видимой части диалога
/// ровно до точки, где откат возможен (с архивацией удаляемого в корзину —
/// ничего не удаляется насовсем), возврат промпта в поле ввода при полном
/// откате последнего запроса, добавление оранжевого чипа отката.
enum RollbackChatApplier {

    struct Dependencies {
        let messages: [Message]
        let sessionID: String
        let homeDirectory: URL
        let removeMessage: (String) -> Void
        let appendMessage: (Message) -> Void
        let restorePrompt: (String) -> Void
    }

    static func apply(chip: RollbackChipData,
                      dependencies: Dependencies,
                      fileManager: FileManager = .default) throws {
        let plan = chip.report.plan
        var removed = removedMessages(plan: plan, messages: dependencies.messages)

        // При полном откате последнего запроса сам запрос исчезает из чата:
        // его текст возвращается в поле ввода.
        if let prompt = plan.promptRestore,
           let target = dependencies.messages.first(where: { $0.id == plan.targetMessageID }),
           !removed.contains(where: { $0.id == target.id }) {
            removed.append(target)
            dependencies.restorePrompt(prompt)
        }

        if !removed.isEmpty {
            _ = try RollbackChatArchive.archive(
                messages: removed,
                sessionID: dependencies.sessionID,
                homeDirectory: dependencies.homeDirectory
            )
            for message in removed.reversed() {
                dependencies.removeMessage(message.id)
            }
        }

        if let content = RollbackChipCodec.encode(chip) {
            dependencies.appendMessage(Message(role: .system, content: content, isFinished: true))
        }
    }

    /// Сообщения, подлежащие удалению: всё, что идёт ПОСЛЕ границы
    /// видимости (`visibilityCutMessageID`).
    private static func removedMessages(plan: RollbackPlan,
                                        messages: [Message]) -> [Message] {
        guard let cutID = plan.visibilityCutMessageID,
              let cutIndex = messages.firstIndex(where: { $0.id == cutID }) else {
            return []
        }
        return Array(messages.dropFirst(cutIndex + 1))
    }
}
