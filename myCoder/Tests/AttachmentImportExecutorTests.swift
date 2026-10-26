import Testing
@testable import myCoder

@Suite("Attachment Import Executor")
struct AttachmentImportExecutorTests {

    @Test("Sync import on main actor updates store immediately")
    @MainActor
    func syncImportUpdatesStore() {
        let store = MessageAttachmentStore()
        let result = ClipboardPasteResult(
            images: [ClipboardImage(base64: "imgdata", mimeType: "image/png")]
        )
        AttachmentImportExecutor.importResult(result, into: store)
        #expect(store.attachedImages.count == 1)
    }
}
