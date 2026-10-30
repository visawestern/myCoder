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

    static func shouldScrollOnSessionChange(oldSessionID: String?, newSessionID: String?) -> Bool {
        guard let newSessionID, !newSessionID.isEmpty else { return false }
        return newSessionID != oldSessionID
    }

    static func showsScrollToBottomButton(isBottomVisible: Bool, messageCount: Int) -> Bool {
        !isBottomVisible && messageCount > 0
    }
}
