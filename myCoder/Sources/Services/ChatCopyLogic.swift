import Foundation

enum ChatCopyResult: Equatable {
    case copied(String)
    case empty
}

enum ChatCopyLogic {
    static func result(from messages: [Message]) -> ChatCopyResult {
        let value = transcript(from: messages)
        return value.isEmpty ? .empty : .copied(value)
    }

    static func transcript(from messages: [Message]) -> String {
        MessageDisplayLogic.messagesForDisplay(messages).compactMap { message -> String? in
            let text = visibleText(for: message)
            guard !text.isEmpty else { return nil }
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role):\n\(text)"
        }
        .joined(separator: "\n\n---\n\n")
    }

    private static func visibleText(for message: Message) -> String {
        var chunks: [String] = []
        for part in MessageDisplayLogic.chatDisplayParts(message.parts) {
            if case .text(let value) = part,
               let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(value) {
                chunks.append(sanitized)
            }
        }
        if chunks.isEmpty,
           let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(message.content) {
            chunks.append(sanitized)
        }
        return chunks.joined(separator: "\n\n")
    }
}

extension Notification.Name {
    static let copyEntireChat = Notification.Name("MiMoCopyEntireChat")
    static let copyEntireChatCompleted = Notification.Name("MiMoCopyEntireChatCompleted")
    static let copyEntireChatUnavailable = Notification.Name("MiMoCopyEntireChatUnavailable")
}
