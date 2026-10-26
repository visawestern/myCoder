import Foundation

/// Audit 2026-09-08: `/api/send-and-wait` used to accept ANY finished
/// assistant row as "answered" — including internal UI status lines such as
/// "Thinking… (K3)" or "Sent via browserAutomation, waiting for response…".
/// That made the debug API report fake success while the vendor had not
/// produced anything yet. This logic distinguishes a real provider answer
/// from local-only status/progress text.
///
/// Route metadata lives in a `routeInfo` part (header chips) since
/// 2026-09-08 and never appears in the answer text, so no footer special
/// case is needed anymore.
enum SendWaitAnswerLogic {
    /// Internal markers a bubble may carry while the turn is still running.
    /// A REAL answer is a finished assistant message that is none of these.
    static let statusMarkers: [String] = [
        "Thinking… (",
        "Waiting for ",
        "Sent via ",
        "waiting for response",
        "Running tools",
        "⏳",
        "Refreshing model catalog",
        "Saved cookies restored",
        "Chat input not found",
        "Approval required before this web-agent action"
    ]

    /// True when the text is a genuine provider answer (not a UI status line,
    /// not a vendor error placeholder — audit 2026-09-09, Qwen's
    /// "The current content is empty, please regenerate." — and not a local
    /// turn error, which the send-and-wait contract reports as status:error).
    static func isRealAnswer(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !WebVendorErrorPlaceholderLogic.isErrorPlaceholder(trimmed) else { return false }
        let errorPrefixes = ["myCoder Auto Free error:", "Web chat was not sent", "Web provider error:"]
        guard !errorPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return false }
        return !statusMarkers.contains { trimmed.contains($0) }
    }
}
