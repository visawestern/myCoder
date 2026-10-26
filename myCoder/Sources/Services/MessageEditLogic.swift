import Foundation

enum MessageEditLogic {

    struct Draft {
        let text: String
        let images: [ClipboardImage]
        let files: [FileInfo]
    }

    static func draft(from message: Message) -> Draft {
        Draft(
            text: messageText(from: message),
            images: imagesFromMessage(message),
            files: message.files ?? []
        )
    }

    static func messageText(from message: Message) -> String {
        var texts: [String] = []
        for part in message.parts {
            if case .text(let value) = part, !value.isEmpty {
                texts.append(value)
            }
        }
        if texts.isEmpty, !message.content.isEmpty {
            texts.append(message.content)
        }
        return texts.joined(separator: "\n\n")
    }

    static func imagesFromMessage(_ message: Message) -> [ClipboardImage] {
        var images: [ClipboardImage] = []
        var seen = Set<String>()

        for part in message.parts {
            if case .image(let base64, let mimeType) = part,
               !base64.isEmpty,
               seen.insert(base64).inserted {
                images.append(ClipboardImage(base64: base64, mimeType: mimeType))
            }
        }

        for image in MessageDisplayLogic.attachedImagesForDisplay(message) where seen.insert(image.base64).inserted {
            images.append(image)
        }

        return images
    }

    static func canEdit(_ message: Message) -> Bool {
        !message.isStreaming && (message.role == .user || message.role == .assistant)
    }

    static func canResend(_ message: Message) -> Bool {
        guard !message.isStreaming else { return false }
        if message.role == .user {
            return !draft(from: message).text.isEmpty || !imagesFromMessage(message).isEmpty
        }
        return message.role == .assistant
    }

    static func shouldShowActions(
        hasToolCalls: Bool,
        isStreaming: Bool,
        canEdit: Bool,
        displayText: String,
        hasAttachments: Bool = false
    ) -> Bool {
        !hasToolCalls
            && !isStreaming
            && (!displayText.isEmpty || hasAttachments)
            && (canEdit || !displayText.isEmpty)
    }
}

extension Notification.Name {
    static let editMessage = Notification.Name("MiMoEditMessage")
    static let resendMessage = Notification.Name("MiMoResendMessage")
    static let retryMessage = Notification.Name("MiMoRetryMessage")
    static let stopGeneration = Notification.Name("MiMoStopGeneration")
    static let undoLastOperation = Notification.Name("MiMoUndoLastOperation")
}
