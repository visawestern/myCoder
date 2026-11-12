import Foundation

/// Chooses the prior conversation turns for one model call.
///
/// Input: the full persisted message list of a chat and, optionally, the id of
/// the user message that started the current turn.
/// Output: every user/assistant message strictly BEFORE that user message.
///
/// Purpose: the model must never receive the current request twice, the
/// in-flight assistant placeholder, or a warning notice that belongs to the
/// current turn. The previous `dropLast(2)` rule cut a REAL assistant answer
/// whenever the send path appended an extra notice — live 2026-11-12 the turn
/// that created `aquarium_3d.html` disappeared from history, so the model
/// stopped knowing the file existed and re-searched for it.
///
/// Dependencies: `Message` and `MessageRole` only. Pure, deterministic and
/// independently testable (`DirectHistorySelectionLogicTests`).
enum DirectHistorySelectionLogic {

    /// Messages before the current user turn, keeping their original order.
    ///
    /// - Parameters:
    ///   - messages: persisted feed of one chat, oldest first.
    ///   - currentUserMessageID: bubble that started this turn. When nil or
    ///     not found, the last user message is used as the boundary (retry
    ///     reuses an existing bubble).
    /// - Returns: user/assistant messages only; system summaries, notices and
    ///   empty placeholders are not model dialogue and are excluded.
    static func priorTurns(from messages: [Message],
                           currentUserMessageID: String? = nil) -> [Message] {
        let boundary: Int
        if let currentUserMessageID,
           let index = messages.lastIndex(where: { $0.id == currentUserMessageID }) {
            boundary = index
        } else if let index = messages.lastIndex(where: { $0.role == .user }) {
            boundary = index
        } else {
            return []
        }
        return messages[..<boundary].filter { $0.role == .user || $0.role == .assistant }
    }
}

/// Builds visible per-turn notices that must NOT be treated as dialogue.
///
/// Input: a human-readable warning text.
/// Output: a finished `.system` message with the warning glyph.
///
/// Purpose: notices used to be persisted as `.assistant`, so they counted as
/// real turns in the history window and pushed actual answers out. A system
/// role keeps them visible in the feed while history/ledger builders ignore
/// them. Depends on `Message` only; tested by `TurnNoticeBuilderTests`.
enum TurnNoticeBuilder {

    /// The persisted notice for a degraded turn.
    static func warningNotice(_ warning: String) -> Message {
        Message(role: .system, content: "⚠️ \(warning)", isFinished: true)
    }

    /// Legacy rows saved before the role fix. They are assistant messages
    /// whose body starts with the warning glyph and must not enter history.
    static func isLegacyNotice(role: String, content: String) -> Bool {
        role == "assistant" && content.hasPrefix("⚠️")
    }
}
