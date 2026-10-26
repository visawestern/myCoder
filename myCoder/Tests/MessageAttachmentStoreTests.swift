import Testing
import Foundation
@testable import myCoder

private struct MockClipboardProvider: ClipboardProviding {
    let result: ClipboardPasteResult

    func consume() -> ClipboardPasteResult {
        result
    }
}

@Suite("Message Attachment Store")
struct MessageAttachmentStoreTests {

    @Test("Import PNG result adds image with base64")
    @MainActor
    func importPNG() {
        let store = MessageAttachmentStore()
        let result = ClipboardPasteResult(
            images: [ClipboardImage(base64: "abc123", mimeType: "image/png")]
        )
        store.importFromPasteboard(using: MockClipboardProvider(result: result))
        #expect(store.attachedImages.count == 1)
        #expect(!store.attachedImages[0].base64.isEmpty)
        #expect(store.lastImportError == nil)
    }

    @Test("Empty import sets lastImportError")
    @MainActor
    func emptyImportSetsError() {
        let store = MessageAttachmentStore()
        store.importFromPasteboard(using: MockClipboardProvider(result: ClipboardPasteResult()))
        #expect(store.attachedImages.isEmpty)
        #expect(store.lastImportError != nil)
    }

    @Test("Import dedupes files by path")
    @MainActor
    func dedupeFiles() {
        let store = MessageAttachmentStore()
        let file = FileInfo(name: "a.swift", type: .swift, path: "/tmp/a.swift")
        let result = ClipboardPasteResult(files: [file, file])
        store.importResult(result)
        #expect(store.attachedFiles.count == 1)
    }

    @Test("Clear removes attachments and error")
    @MainActor
    func clear() {
        let store = MessageAttachmentStore()
        store.importResult(ClipboardPasteResult(
            images: [ClipboardImage(base64: "x", mimeType: "image/png")],
            files: [FileInfo(name: "a.txt", type: .unknown, path: "/tmp/a.txt")]
        ))
        store.clear()
        #expect(store.attachedImages.isEmpty)
        #expect(store.attachedFiles.isEmpty)
        #expect(store.lastImportError == nil)
    }

    @Test("Import from drop result works")
    @MainActor
    func importDropResult() {
        let store = MessageAttachmentStore()
        store.importResult(ClipboardPasteResult(
            images: [ClipboardImage(base64: "drop", mimeType: "image/png")]
        ))
        #expect(store.attachedImages.count == 1)
        #expect(store.attachedImages[0].base64 == "drop")
    }
}
