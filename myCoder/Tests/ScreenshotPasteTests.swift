import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Screenshot Pasteboard", .serialized)
struct ScreenshotPasteboardTests {

    @Test("ClipboardProvider reads HEIC screenshot data")
    func consumeHEIC() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 5, height: 5))
            image.lockFocus()
            NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 5, height: 5))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let heic = rep.representation(using: .jpeg2000, properties: [:]) else {
                Issue.record("Failed to create HEIC/JPEG2000 data")
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(heic, forType: NSPasteboard.PasteboardType("public.heic"))

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider reads screenshot file URL from pasteboard item")
    func consumeScreenshotFileURLItem() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
            let image = NSImage(size: NSSize(width: 6, height: 6))
            image.lockFocus()
            NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 6, height: 6))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }
            try png.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            pb.writeObjects([item])

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider prefers image bytes when file URL image is missing")
    func consumeImageBytesWhenFileMissing() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let missingURL = URL(fileURLWithPath: "/tmp/Screenshot \(UUID().uuidString).png")
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(missingURL.absoluteString, forType: .fileURL)
            item.setData(png, forType: .png)
            pb.writeObjects([item])

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider reads dynamic screenshot UTI from pasteboard item")
    func consumeDynamicScreenshotUTI() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 8, height: 8))
            image.lockFocus()
            NSColor.orange.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let dynamicType = NSPasteboard.PasteboardType("com.apple.screen-capture")
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: dynamicType)
            pb.writeObjects([item])

            #expect(PasteboardAttachmentDetector.hasAttachments())
            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider reads promised screenshot data via loadData")
    func consumePromisedScreenshotData() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 7, height: 7))
            image.lockFocus()
            NSColor.purple.drawSwatch(in: NSRect(x: 0, y: 0, width: 7, height: 7))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let provider = PromisedPNGProvider(png: png)
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.png])

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([item])

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }
}

private final class PromisedPNGProvider: NSObject, NSPasteboardItemDataProvider {
    private let png: Data

    init(png: Data) {
        self.png = png
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setData(png, forType: type)
    }
}

@Suite("Chat Paste Routing")
struct ChatPasteRoutingTests {

    @Test("Intercept paste when attachment text view focused and pasteboard has image")
    func interceptWhenAttachmentTextViewFocusedWithImage() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            let textView = AttachmentPasteTextView()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: textView,
                    isKeyWindow: true
                )
            )
        }
    }

    @Test("Do not intercept paste when attachment text view focused and pasteboard is empty")
    func skipWhenAttachmentTextViewFocusedWithoutImage() {
        PasteboardIsolation.withExclusiveAccess {
            NSPasteboard.general.clearContents()
            let textView = AttachmentPasteTextView()
            #expect(
                ChatPasteRoutingLogic.shouldOfferChatPasteImport(
                    firstResponder: textView,
                    isKeyWindow: true
                )
            )
            #expect(
                !ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: textView,
                    isKeyWindow: true
                )
            )
        }
    }

    @Test("Intercept paste when attachment scroll view focused and pasteboard has image")
    func interceptWhenAttachmentScrollViewFocusedWithImage() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            let scrollView = AttachmentPasteScrollView()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: scrollView,
                    isKeyWindow: true
                )
            )
        }
    }

    @Test("Intercept paste when chat panel has no focused text field and pasteboard has image")
    func interceptWhenNoFieldFocused() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: nil,
                    isKeyWindow: true
                )
            )
        }
    }

    @Test("Skip paste intercept for sidebar search fields even with image on pasteboard")
    func skipStandardTextField() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            let field = NSTextField()
            #expect(
                !ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: field,
                    isKeyWindow: true
                )
            )
        }
    }

    @Test("Skip paste intercept when window is not key")
    func skipWhenNotKeyWindow() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            #expect(
                !ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: nil,
                    isKeyWindow: false
                )
            )
        }
    }

    @Test("Intercept paste for transcript NSTextView when pasteboard has image")
    func interceptGenericTextViewWithImage() throws {
        try PasteboardIsolation.withExclusiveAccess {
            try seedPNG()
            let textView = NSTextView()
            #expect(
                ChatPasteRoutingLogic.shouldInterceptPaste(
                    firstResponder: textView,
                    isKeyWindow: true
                )
            )
        }
    }

    private func seedPNG() throws {
        // Round 12: seed through the shared process-wide lock (parallel suites
        // must not race on the real NSPasteboard.general).
        try PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw SeedError.failed
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
        }
    }

    private enum SeedError: Error {
        case failed
    }
}
