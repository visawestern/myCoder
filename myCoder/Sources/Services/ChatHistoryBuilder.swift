import Foundation

/// Builds conversation history for stateless HTTP chat providers so local /
/// custom / web models actually see prior turns (audit P1/P2/P3). Pure and
/// testable — the view adapts its `Message` list into simple role/content
/// tuples and passes them here.
enum ChatHistoryBuilder {
    struct Turn: Equatable {
        let role: String       // "user" | "assistant" | "system"
        let content: String
        let isFinished: Bool
    }

    /// Convert prior turns into DirectChatMessages, keeping only finished,
    /// non-empty user/assistant turns, dropping the trailing in-flight
    /// assistant placeholder, and capping to the last `maxTurns` messages.
    static func history(from turns: [Turn], maxTurns: Int = 20) -> [DirectChatMessage] {
        let cleaned = turns.compactMap { turn -> DirectChatMessage? in
            guard turn.role == "user" || turn.role == "assistant" else { return nil }
            let text = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }        // skip empty streaming placeholders
            guard turn.isFinished || turn.role == "user" else { return nil }
            return DirectChatMessage(role: turn.role, content: turn.content)
        }
        // Keep the most recent maxTurns.
        if cleaned.count > maxTurns { return Array(cleaned.suffix(maxTurns)) }
        return cleaned
    }

    /// The full message list for a new user message: system + history + the new
    /// user text. `priorTurns` should NOT include the new user message or the
    /// empty assistant placeholder.
    /// E01: `parts` carries OpenAI-style multimodal parts (image_url…) so the
    /// direct OpenAI-compatible path receives attachments, not just text.
    static func messages(systemPrompt: String?,
                        priorTurns: [Turn],
                        userText: String,
                        parts: [[String: Any]]? = nil,
                        maxTurns: Int = 20) -> [DirectChatMessage] {
        var msgs: [DirectChatMessage] = []
        if let sys = systemPrompt, !sys.isEmpty {
            msgs.append(DirectChatMessage(role: "system", content: sys))
        }
        msgs.append(contentsOf: history(from: priorTurns, maxTurns: maxTurns))
        msgs.append(DirectChatMessage(role: "user", content: userText, parts: parts))
        return msgs
    }

    /// Harness-tax C1: outgoing initial-context size in UTF-8 bytes
    /// (system + history + new user text). Text only, mirrors `messages`
    /// minus multimodal parts.
    static func contextBytes(systemPrompt: String?,
                             priorTurns: [Turn],
                             userText: String) -> Int {
        var total = 0
        if let sys = systemPrompt, !sys.isEmpty {
            total += sys.utf8.count
        }
        total += history(from: priorTurns).reduce(0) { $0 + $1.content.utf8.count }
        total += userText.utf8.count
        return total
    }
}
