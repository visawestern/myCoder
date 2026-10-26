import Testing
import AppKit
@testable import myCoder

@Suite("Paste Routing Integration", .serialized)
struct PasteRoutingIntegrationTests {

    private static let applePNGType = NSPasteboard.PasteboardType("Apple PNG pasteboard type")

    @Test("AttachmentPasteTextView import callback populates store")
    @MainActor
    func textViewImportCallback() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let store = MessageAttachmentStore()
            let textView = AttachmentPasteTextView()
            textView.onImportFromPasteboard = {
                AttachmentImportExecutor.importFromPasteboard(into: store)
            }
            textView.onImportFromPasteboard?()
            #expect(store.attachedImages.count == 1)
            #expect(store.lastImportError == nil)
        }
    }

    @Test("AttachmentPasteScrollView import callback populates store")
    @MainActor
    func scrollViewImportCallback() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let store = MessageAttachmentStore()
            let scrollView = AttachmentPasteScrollView()
            scrollView.onImportFromPasteboard = {
                AttachmentImportExecutor.importFromPasteboard(into: store)
            }
            scrollView.onImportFromPasteboard?()
            #expect(store.attachedImages.count == 1)
        }
    }

    @Test("Try import returns false for empty pasteboard")
    @MainActor
    func tryImportEmptyPasteboard() {
        PasteboardIsolation.withExclusiveAccess {
            NSPasteboard.general.clearContents()
            let store = MessageAttachmentStore()
            #expect(!AttachmentImportExecutor.tryImportFromPasteboard(into: store))
            #expect(store.attachedImages.isEmpty)
            #expect(store.lastImportError == nil)
        }
    }

    @Test("Bridge offers chat paste import when toolbar has focus")
    func bridgeOffersPasteWithoutTextFocus() {
        let button = NSButton()
        #expect(
            ChatPasteRoutingLogic.shouldOfferChatPasteImport(
                firstResponder: button,
                isKeyWindow: true,
                chatComposerIsActive: true
            )
        )
    }

    @Test("Bridge intercepts paste when toolbar has focus and pasteboard has image")
    func bridgeInterceptsWithoutTextFocus() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let button = NSButton()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: button,
                    isKeyWindow: true,
                    chatComposerIsActive: true
                )
            )
        }
    }

    @Test("Bridge does not intercept sidebar search field")
    func bridgeSkipsSidebarSearch() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let field = NSTextField()
            #expect(
                !ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: field,
                    isKeyWindow: true,
                    chatComposerIsActive: true
                )
            )
        }
    }

    @Test("Bridge intercepts when chat composer active and nothing focused")
    func bridgeInterceptsNilResponder() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: nil,
                    isKeyWindow: true,
                    chatComposerIsActive: true
                )
            )
        }
    }

    @Test("Bridge skips when chat composer inactive")
    func bridgeSkipsWhenComposerInactive() {
        #expect(
            !ChatPasteRoutingLogic.shouldInterceptPaste(
                firstResponder: nil,
                isKeyWindow: true,
                chatComposerIsActive: false
            )
        )
    }

    @Test("Attachment text view handles paste menu action")
    @MainActor
    func textViewPasteMenuAction() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let store = MessageAttachmentStore()
            let textView = AttachmentPasteTextView()
            textView.onImportFromPasteboard = {
                AttachmentImportExecutor.importFromPasteboard(into: store)
            }
            textView.paste(nil)
            #expect(store.attachedImages.count == 1)
        }
    }

    @Test("Attachment scroll view handles paste menu action")
    @MainActor
    func scrollViewPasteMenuAction() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNGPasteboard()
            let store = MessageAttachmentStore()
            let scrollView = AttachmentPasteScrollView()
            let textView = AttachmentPasteTextView()
            scrollView.documentView = textView
            scrollView.onImportFromPasteboard = {
                AttachmentImportExecutor.importFromPasteboard(into: store)
            }
            scrollView.importAttachmentsFromPasteboard()
            #expect(store.attachedImages.count == 1)
        }
    }

    private func seedPNGPasteboard() throws {
        // Round 12: seed through the shared process-wide lock so parallel
        // clipboard suites can't race on the real NSPasteboard.general.
        try PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 5, height: 5))
            image.lockFocus()
            NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 5, height: 5))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw SeedError.failed
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(png, forType: Self.applePNGType)
            pb.writeObjects([item])
        }
    }

    private enum SeedError: Error {
        case failed
    }
}
