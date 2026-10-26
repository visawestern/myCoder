import Testing
import Foundation
import AppKit
import SwiftUI
@testable import myCoder

@Suite("Clipboard Paste", .serialized)
struct ClipboardPasteTests {

    @Test("Image file URL is attached as clipboard image")
    func imageFileURLBecomesImage() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("paste-test-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG")
            return
        }
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ClipboardPasteLogic.parseFileURLs([url])
        #expect(result.images.count == 1)
        #expect(result.files.isEmpty)
        #expect(!result.images[0].base64.isEmpty)
    }

    @Test("Non-image file URL is attached as file")
    func textFileURLBecomesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("paste-test-\(UUID().uuidString).swift")
        try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ClipboardPasteLogic.parseFileURLs([url])
        #expect(result.files.count == 1)
        #expect(result.images.isEmpty)
        #expect(result.files[0].name == url.lastPathComponent)
        #expect(result.files[0].type == .swift)
        #expect(result.files[0].path == url.path)
    }

    @Test("Apply paste result appends images and files without duplicating paths")
    func applyPasteResultDedupesFiles() {
        var images: [ClipboardImage] = []
        var files: [FileInfo] = []
        let file = FileInfo(name: "a.swift", type: .swift, path: "/tmp/a.swift")

        MessageAttachmentState.apply(
            ClipboardPasteResult(images: [ClipboardImage(base64: "img", mimeType: "image/png")], files: [file]),
            images: &images,
            files: &files
        )
        MessageAttachmentState.apply(
            ClipboardPasteResult(files: [file]),
            images: &images,
            files: &files
        )

        #expect(images.count == 1)
        #expect(files.count == 1)
    }

    @Test("Can send when only files are attached")
    func canSendWithFilesOnly() {
        #expect(
            MessageSendValidation.canSend(
                text: "   ",
                images: [],
                files: [FileInfo(name: "doc.pdf", type: .unknown, path: "/tmp/doc.pdf")]
            )
        )
    }

    @Test("Can send when only images are attached")
    func canSendWithImagesOnly() {
        #expect(
            MessageSendValidation.canSend(
                text: "",
                images: [ClipboardImage(base64: "x", mimeType: "image/png")],
                files: []
            )
        )
    }

    @Test("ClipboardProvider prefers image bytes over non-image file URL when both present")
    func consumePrefersImagesWhenMixedWithFileURL() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("paste-test-\(UUID().uuidString).swift")
            try "struct A {}".write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])

            let testImage = NSImage(size: NSSize(width: 2, height: 2))
            testImage.lockFocus()
            NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
            testImage.unlockFocus()
            if let tiff = testImage.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider returns image when pasteboard has image only")
    func consumeImageOnly() {
        PasteboardIsolation.withExclusiveAccess {
            let testImage = NSImage(size: NSSize(width: 2, height: 2))
            testImage.lockFocus()
            NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
            testImage.unlockFocus()

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(testImage.tiffRepresentation, forType: .tiff)

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider reads screenshot-style NSImage object")
    func consumeScreenshotObject() {
        PasteboardIsolation.withExclusiveAccess {
            let testImage = NSImage(size: NSSize(width: 8, height: 8))
            testImage.lockFocus()
            NSColor.orange.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
            testImage.unlockFocus()

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([testImage])

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("Binding apply updates attached images array")
    func bindingApplyUpdatesImages() {
        var images: [ClipboardImage] = []
        var files: [FileInfo] = []
        let imagesBinding = Binding(get: { images }, set: { images = $0 })
        let filesBinding = Binding(get: { files }, set: { files = $0 })

        MessageAttachmentState.apply(
            ClipboardPasteResult(images: [ClipboardImage(base64: "shot", mimeType: "image/png")]),
            images: imagesBinding,
            files: filesBinding
        )

        #expect(images.count == 1)
        #expect(images[0].base64 == "shot")
    }

    @Test("ClipboardProvider reads native macOS screenshot PNG pasteboard")
    func consumeNativeScreenshotPNG() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 6, height: 6))
            image.lockFocus()
            NSColor.cyan.drawSwatch(in: NSRect(x: 0, y: 0, width: 6, height: 6))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            pb.setData(png, forType: NSPasteboard.PasteboardType("Apple PNG pasteboard type"))

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardProvider falls back to PNG when file URL is unreadable")
    func consumeFallsBackWhenFileURLUnreadable() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            NSColor.magenta.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let missingURL = URL(fileURLWithPath: "/tmp/mimo-missing-screenshot-\(UUID().uuidString).png")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([missingURL as NSURL])
            pb.setData(png, forType: .png)

            let result = ClipboardProvider().consume()
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("ClipboardImage encodes PNG-backed NSImage without tiffRepresentation")
    func clipboardImageEncodesFromPNGBackedNSImage() throws {
        let image = NSImage(size: NSSize(width: 3, height: 3))
        image.lockFocus()
        NSColor.yellow.drawSwatch(in: NSRect(x: 0, y: 0, width: 3, height: 3))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG")
            return
        }

        guard let pngBacked = NSImage(data: png) else {
            Issue.record("Failed to create PNG-backed NSImage")
            return
        }

        let clip = ClipboardImage.from(nsImage: pngBacked)
        #expect(clip != nil)
        #expect(clip?.base64.isEmpty == false)
    }
}
