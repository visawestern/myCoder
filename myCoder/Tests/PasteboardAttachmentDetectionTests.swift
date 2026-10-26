import Testing
import AppKit
@testable import myCoder

@Suite("Pasteboard Attachment Detection", .serialized)
struct PasteboardAttachmentDetectionTests {

    private static let applePNGType = NSPasteboard.PasteboardType("Apple PNG pasteboard type")
    private static let nextTIFFType = NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")

    @Test("Synthetic screencapture pasteboard is detected")
    func syntheticScreencaptureDetected() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedSyntheticScreencapturePasteboard()
            #expect(PasteboardAttachmentDetector.hasAttachments())
        }
    }

    @Test("hasAttachments implies consume returns data")
    func hasAttachmentsImpliesConsumeNonEmpty() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedSyntheticScreencapturePasteboard()
            guard PasteboardAttachmentDetector.hasAttachments() else {
                Issue.record("Expected synthetic pasteboard to be detected")
                return
            }
            let result = ClipboardProvider().consume()
            #expect(!result.isEmpty)
            #expect(result.images.count == 1)
            #expect(result.images[0].base64.count > 20)
        }
    }

    @Test("Empty pasteboard is not detected")
    func emptyPasteboardNotDetected() {
        PasteboardIsolation.withExclusiveAccess {
            NSPasteboard.general.clearContents()
            #expect(!PasteboardAttachmentDetector.hasAttachments())
            #expect(ClipboardProvider().consume().isEmpty)
        }
    }

    @Test("Stale file URL with inline PNG bytes is detected and consumed")
    func staleFileURLWithInlineBytes() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let png = try makePNGData()
            let missingURL = URL(fileURLWithPath: "/tmp/Screenshot \(UUID().uuidString).png")
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(missingURL.absoluteString, forType: .fileURL)
            item.setData(png, forType: .png)
            pb.writeObjects([item])

            #expect(PasteboardAttachmentDetector.hasAttachments())
            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    private func seedSyntheticScreencapturePasteboard() throws {
        // Round 12: seed through the shared process-wide lock (parallel suites
        // must not race on the real NSPasteboard.general).
        try PasteboardIsolation.withExclusiveAccess {
            let png = try makePNGData()
            let image = NSImage(size: NSSize(width: 8, height: 8))
            image.lockFocus()
            NSColor.orange.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation else {
                throw TestError.seedFailed
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(png, forType: Self.applePNGType)
            item.setData(tiff, forType: .tiff)
            item.setData(tiff, forType: Self.nextTIFFType)
            pb.writeObjects([item])
        }
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 6, height: 6))
        image.lockFocus()
        NSColor.cyan.drawSwatch(in: NSRect(x: 0, y: 0, width: 6, height: 6))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw TestError.seedFailed
        }
        return png
    }

    private enum TestError: Error {
        case seedFailed
    }
}
