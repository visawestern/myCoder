import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Text Paste Routing", .serialized)
struct TextPasteRoutingTests {

    @Test("Plain text data is not accepted as a PNG image")
    func textDataRejectedAsPNG() {
        let text = "This is definitely not an image, just a long plain-text clipboard payload."
        let data = Data(text.utf8)
        #expect(ClipboardImage(imageData: data, mimeType: "image/png") == nil)
    }

    @Test("Plain text data is not accepted under any raw image mime type")
    func textDataRejectedForAllMimeTypes() {
        let data = Data(String(repeating: "lorem ipsum dolor sit amet ", count: 10).utf8)
        for mime in ["image/png", "image/tiff", "image/jpeg", "image/heic", "image/heif"] {
            #expect(ClipboardImage(imageData: data, mimeType: mime) == nil, "accepted text as \(mime)")
        }
    }

    @Test("Valid PNG data is still accepted")
    func validPNGStillAccepted() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to build PNG fixture")
            return
        }
        #expect(ClipboardImage(imageData: png, mimeType: "image/png") != nil)
    }

    @Test("Pasteboard with only plain text yields no attachments")
    func plainTextPasteboardYieldsNoAttachments() {
        PasteboardIsolation.withExclusiveAccess {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(
                "Plain multiline text\nthat is longer than thirty-two bytes\nand must stay text on paste.",
                forType: .string
            )

            let result = ClipboardProvider().consume()
            #expect(result.images.isEmpty)
            #expect(result.files.isEmpty)
        }
    }

    @Test("Pasteboard with rich text types yields no attachments")
    func richTextPasteboardYieldsNoAttachments() {
        PasteboardIsolation.withExclusiveAccess {
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            let text = String(repeating: "styled text payload ", count: 8)
            item.setString(text, forType: .string)
            item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
            pb.writeObjects([item])

            let result = ClipboardProvider().consume()
            #expect(result.images.isEmpty)
            #expect(result.files.isEmpty)
        }
    }
}
