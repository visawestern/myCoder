import Foundation

struct ChatScrollRevision: Equatable {
    let messageCount: Int
    let lastMessageID: String?
    let content: String
    let reasoning: String
    let partCount: Int
    let isStreaming: Bool
}

enum ChatScrollLogic {
    static let bottomAnchorID = "chat-bottom-anchor"

    /// Breathing room between the newest message and the composer, so the last
    /// bubble never sits flush against the input panel (user directive).
    static let bottomContentInset: CGFloat = 20

    /// The bottom sentinel counts as visible when it reaches the viewport's
    /// bottom edge (inside it, intersecting it, or within `tolerance` just
    /// below it). Unknown frames report `nil` so callers keep their previous
    /// state instead of jumping.
    static func bottomVisibility(
        bottomFrame: CGRect,
        viewport: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool? {
        guard !viewport.isEmpty, bottomFrame.height > 0 else { return nil }
        if viewport.intersects(bottomFrame) { return true }
        let nearBottom = bottomFrame.maxY >= viewport.maxY - tolerance
            && bottomFrame.minY <= viewport.maxY + tolerance
        return nearBottom
    }

    /// Auto-scroll is suppressed for this long after the user's last wheel
    /// scroll, so reading older messages is never yanked back to the bottom
    /// while the pin state (measured from layout preferences) is still
    /// catching up.
    static let userScrollSuppression: TimeInterval = 0.5

    /// While the user is actively scrolling UP (reading older content), the
    /// auto-scroll must not fight them at all — even after the short
    /// suppression window, because a streaming answer grows below and a
    /// forced bottom-jump would yank the reader out of the text they are
    /// reading. This is the time window during which an upward-reading user
    /// is protected from auto-scroll.
    static let upwardReadingProtection: TimeInterval = 4.0

    /// Direction of the user's last wheel gesture.
    enum WheelDirection: String, Equatable {
        case up
        case down
    }

    /// True when the user has recently scrolled UP (protecting their reading
    /// position) and the auto-scroll should therefore not jump to the bottom.
    static func shouldSuppressAutoScroll(
        lastWheelAt: Date,
        lastWheelDirection: WheelDirection?,
        now: Date = Date(),
        protection: TimeInterval = upwardReadingProtection
    ) -> Bool {
        guard lastWheelDirection == .up else { return false }
        return now.timeIntervalSince(lastWheelAt) < protection
    }

    /// Minimum gap between two auto-scrolls. Streaming updates the revision
    /// on every token; throttling coalesces a burst into one scroll per chunk
    /// instead of one scroll per token (which makes the chat dart around).
    static let minScrollInterval: TimeInterval = 0.05

    /// Schedule coalescing: after a revision, wait a beat so the layout has
    /// the newest frames before deciding whether to scroll.
    static let coalesceNanoseconds: UInt64 = 16_000_000

    /// The bottom anchor is considered "glued" to the viewport when its bottom
    /// edge sits within `slack` points of the viewport's bottom edge. When
    /// glued, no scroll is needed — scrolling anyway fights the user and
    /// causes micro-jitter.
    static let glueSlack: CGFloat = 6

    static func anchorIsGlued(
        bottomFrame: CGRect,
        viewport: CGRect,
        slack: CGFloat = glueSlack
    ) -> Bool {
        guard !viewport.isEmpty, bottomFrame.height > 0 else { return false }
        return abs(bottomFrame.maxY - viewport.maxY) <= slack
    }

    static func revision(messages: [Message]) -> ChatScrollRevision {
        let last = messages.last
        return ChatScrollRevision(
            messageCount: messages.count,
            lastMessageID: last?.id,
            content: last?.content ?? "",
            reasoning: last?.reasoning ?? "",
            partCount: last?.parts.count ?? 0,
            isStreaming: last?.isStreaming ?? false
        )
    }

    static func shouldAutoScroll(wasAtBottom: Bool) -> Bool {
        wasAtBottom
    }

    /// A freshly appended message is a hard reason to follow: the user asked
    /// for the latest state. The glued-anchor check can lag a layout pass, so
    /// the newest message id is more reliable than the anchor frame.
    ///
    /// Growth alone is not enough: loading older messages prepends to the
    /// feed, so the count grows while the newest message stays the same. That
    /// is a history read, not a new answer — scrolling to the bottom would
    /// yank the user away from what they just opened (user directive).
    static func shouldScrollAfterNewMessage(
        oldCount: Int,
        newCount: Int,
        oldLastMessageID: String?,
        newLastMessageID: String?
    ) -> Bool {
        guard newCount > oldCount else { return false }
        return newLastMessageID != oldLastMessageID
    }

    static func shouldScrollOnSessionChange(oldSessionID: String?, newSessionID: String?) -> Bool {
        guard let newSessionID, !newSessionID.isEmpty else { return false }
        return newSessionID != oldSessionID
    }

    static func showsScrollToBottomButton(isBottomVisible: Bool, messageCount: Int) -> Bool {
        !isBottomVisible && messageCount > 0
    }
}
