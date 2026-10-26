import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Automated Clipboard Import", .serialized)
struct AutomatedClipboardImportTests {

    private static let applePNGType = NSPasteboard.PasteboardType("Apple PNG pasteboard type")
    private static let nextTIFFType = NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")

    @Test("Synthetic screencapture-like pasteboard is consumed")
    func syntheticScreencapturePasteboard() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 8, height: 8))
            image.lockFocus()
            NSColor.orange.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG/TIFF test data")
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(png, forType: Self.applePNGType)
            item.setData(tiff, forType: .tiff)
            item.setData(tiff, forType: Self.nextTIFFType)
            pb.writeObjects([item])

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.images[0].base64.count > 20)
        }
    }

    @Test("Store imports synthetic screencapture pasteboard end-to-end")
    @MainActor
    func storeImportsSyntheticPasteboard() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 10, height: 10))
            image.lockFocus()
            NSColor.purple.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG/TIFF test data")
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(png, forType: Self.applePNGType)
            item.setData(tiff, forType: .tiff)
            pb.writeObjects([item])

            let store = MessageAttachmentStore()
            store.importFromPasteboard()
            #expect(store.attachedImages.count == 1)
            #expect(store.attachedImages[0].base64.count > 20)
            #expect(store.lastImportError == nil)
        }
    }
}
