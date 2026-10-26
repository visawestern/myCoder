import AppKit

enum PasteResponderKind {
    /// Chat prompt view that imports attachments and pastes text on its own.
    case attachmentTextView
    /// Regular NSTextView (e.g. the empty-state prompt) that pastes text natively.
    case plainTextView
    /// NSTextField or a field editor backing one (search fields, forms).
    case textField
    case other
}

/// Decides whether the global Cmd+V monitor should stay out of the way and let
/// the focused control handle paste through the normal responder chain.
enum PasteRoutingDecision {

    static func kind(of responder: AnyObject?) -> PasteResponderKind {
        if responder is AttachmentPasteTextView { return .attachmentTextView }
        if let textView = responder as? NSTextView {
            return textView.isFieldEditor ? .textField : .plainTextView
        }
        if responder is NSTextField { return .textField }
        return .other
    }

    static func shouldPassThrough(responder: PasteResponderKind, pasteboardHasAttachments: Bool) -> Bool {
        switch responder {
        case .attachmentTextView, .textField:
            return true
        case .plainTextView:
            return !pasteboardHasAttachments
        case .other:
            return false
        }
    }
}
