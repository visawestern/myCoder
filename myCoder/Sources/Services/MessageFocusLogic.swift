import Foundation

/// One-shot request to bring a concrete message into view. Created when the
/// user taps a tool-approval notification; carrying the message id is what
/// makes the tap land on the card that raised the alert instead of only
/// opening the chat at its newest message.
struct MessageFocusRequest: Equatable, Identifiable {
    let sessionID: String
    let messageID: String
    /// A fresh token per request, so tapping the same notification twice
    /// re-triggers the scroll even though session and message are unchanged.
    let token: UUID

    var id: UUID { token }

    init(sessionID: String, messageID: String, token: UUID = UUID()) {
        self.sessionID = sessionID
        self.messageID = messageID
        self.token = token
    }
}

/// Pure rules for applying a focus request to the currently loaded history.
enum MessageFocusLogic {
    static let maxOlderPageLoads = 20

    static func applies(_ request: MessageFocusRequest?, to sessionID: String?) -> Bool {
        guard let request, let sessionID else { return false }
        return request.sessionID == sessionID
    }

    static func isLoaded(messageID: String, in messages: [Message]) -> Bool {
        messages.contains { $0.id == messageID }
    }

    /// Older pages are only worth loading while the target is still missing
    /// and the store says there is more history to fetch.
    static func shouldLoadOlderPage(
        messageID: String,
        messages: [Message],
        hasMoreMessages: Bool,
        attempts: Int
    ) -> Bool {
        guard !isLoaded(messageID: messageID, in: messages) else { return false }
        guard hasMoreMessages else { return false }
        return attempts < maxOlderPageLoads
    }
}
