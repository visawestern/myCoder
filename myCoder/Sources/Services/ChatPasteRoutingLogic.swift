import AppKit

enum ChatPasteRoutingLogic {
    /// Returns true when ⌘V in the chat window should attempt attachment import
    /// before falling back to normal text paste.
    static func shouldOfferChatPasteImport(
        firstResponder: NSResponder?,
        isKeyWindow: Bool,
        chatComposerIsActive: Bool = true
    ) -> Bool {
        guard chatComposerIsActive, isKeyWindow else { return false }

        if let responder = firstResponder,
           responder is NSTextField || responder is NSSecureTextField {
            return false
        }

        return true
    }

    /// Legacy helper — true when import would succeed right now.
    static func shouldInterceptPaste(
        firstResponder: NSResponder?,
        isKeyWindow: Bool,
        chatComposerIsActive: Bool = true,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard shouldOfferChatPasteImport(
            firstResponder: firstResponder,
            isKeyWindow: isKeyWindow,
            chatComposerIsActive: chatComposerIsActive
        ) else {
            return false
        }
        return PasteboardAttachmentDetector.hasAttachments(on: pasteboard)
            || !ClipboardProvider().consume(on: pasteboard).isEmpty
    }
}
