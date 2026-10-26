import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Live Clipboard Probe", .serialized, .enabled(if: ProcessInfo.processInfo.environment["MIMO_CLIPBOARD_PROBE"] == "1"))
struct LiveClipboardProbeTests {

    @Test("Live pasteboard contains importable image")
    func livePasteboardHasImage() {
        let pb = NSPasteboard.general
        let types = pb.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
        let result = ClipboardProvider().consume()

        #expect(!result.isEmpty, "Live pasteboard empty; types: \(types)")
        #expect(result.images.count >= 1, "Expected image in live pasteboard; types: \(types)")
        #expect(result.images[0].base64.count > 100, "Base64 too short; types: \(types)")
    }

    @Test("Live pasteboard imports into MessageAttachmentStore")
    @MainActor
    func liveStoreImport() {
        let pb = NSPasteboard.general
        let types = pb.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
        let store = MessageAttachmentStore()
        store.importFromPasteboard()

        #expect(store.attachedImages.count >= 1, "Store import failed; types: \(types)")
        #expect(store.attachedImages[0].base64.count > 100)
        #expect(store.lastImportError == nil)
    }
}
