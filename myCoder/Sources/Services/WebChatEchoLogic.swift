import Foundation

/// Audit 2026-09-08 (Kimi): while waiting for an answer, the polled DOM text
/// can stabilize on OUR OWN just-sent message (it renders before generation
/// starts) or on its first streaming token during a burst gap. Finalizing on
/// either produces a fake "answer". This logic recognizes our own echo so
/// `awaitResponse` keeps polling until generation is observed.
enum WebChatEchoLogic {
    /// True when `polled` is plausibly our own just-sent message rather than
    /// a model answer: normalized EXACT equality only. Containment checks are
    /// deliberately rejected (audit 2026-09-08, live: Claude answered the
    /// exact requested string "TEST-OK-CLAUDE" — a substring of the prompt —
    /// and a contains-based guard classified the real answer as our echo,
    /// stalling the turn until timeout). Kimi's own-message render is exact
    /// equality and stays guarded; degenerate short inputs never match.
    static func isEcho(_ polled: String, of sent: String) -> Bool {
        let a = normalized(polled)
        let b = normalized(sent)
        guard a.count >= 4, b.count >= 4 else { return false }
        return a == b
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
