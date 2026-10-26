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
