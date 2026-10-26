import Testing
@testable import myCoder

@Suite("Paste Routing Decision")
struct PasteRoutingDecisionTests {

    @Test("Attachment-aware text view always handles its own paste")
    func attachmentTextViewPassesThrough() {
        #expect(PasteRoutingDecision.shouldPassThrough(responder: .attachmentTextView, pasteboardHasAttachments: true))
        #expect(PasteRoutingDecision.shouldPassThrough(responder: .attachmentTextView, pasteboardHasAttachments: false))
    }

    @Test("Plain text view keeps normal paste for text, yields for attachments")
    func plainTextViewYieldsOnlyForAttachments() {
        #expect(PasteRoutingDecision.shouldPassThrough(responder: .plainTextView, pasteboardHasAttachments: false))
        #expect(!PasteRoutingDecision.shouldPassThrough(responder: .plainTextView, pasteboardHasAttachments: true))
    }

    @Test("Text fields are never hijacked")
    func textFieldPassesThrough() {
        #expect(PasteRoutingDecision.shouldPassThrough(responder: .textField, pasteboardHasAttachments: true))
        #expect(PasteRoutingDecision.shouldPassThrough(responder: .textField, pasteboardHasAttachments: false))
    }

    @Test("Non-text responders are handled by the coordinator")
    func otherResponderIntercepted() {
        #expect(!PasteRoutingDecision.shouldPassThrough(responder: .other, pasteboardHasAttachments: true))
        #expect(!PasteRoutingDecision.shouldPassThrough(responder: .other, pasteboardHasAttachments: false))
    }
}
