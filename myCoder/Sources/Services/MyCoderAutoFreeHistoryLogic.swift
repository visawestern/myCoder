import Foundation

/// Builds the stateless conversation history sent to myCoder Auto Free.
/// The current user message is supplied separately so attachments stay on the
/// current request; only finished, non-empty prior user/assistant turns enter.
enum MyCoderAutoFreeHistoryLogic {
    struct Turn: Equatable {
        let role: String
        let content: String
        let isFinished: Bool
    }

    static func history(from turns: [Turn], maxTurns: Int = 20) -> [Turn] {
        let cleaned = turns.filter { turn in
            guard turn.role == "user" || turn.role == "assistant" else { return false }
            guard !turn.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return turn.isFinished
        }
        guard maxTurns > 0 else { return [] }
        guard cleaned.count > maxTurns else { return cleaned }
        return Array(cleaned.suffix(maxTurns))
    }
}
