import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("File Drop", .serialized)
struct FileDropTests {

    @Test("Extracts file URLs from drag pasteboard")
    func extractsFileURLs() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("drop-\(UUID().uuidString).swift")
            try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.writeObjects([url as NSURL])

            let urls = FileDropLogic.fileURLs(from: pb)
            #expect(urls.count == 1)
            #expect(urls[0].path == url.path)
        }
    }

    @Test("Extracts legacy NSFilenamesPboardType paths")
    func extractsLegacyFilenames() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("drop-\(UUID().uuidString).txt")
            try "hello".write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

            let urls = FileDropLogic.fileURLs(from: pb)
            #expect(urls.count == 1)
            #expect(urls[0].path == url.path)
        }
    }

    @Test("Parses dropped image file as attachment image")
    func droppedImageFile() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("drop-\(UUID().uuidString).png")
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

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.writeObjects([url as NSURL])

            let result = FileDropLogic.parse(pasteboard: pb)
            #expect(result.images.count == 1)
            #expect(result.files.isEmpty)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("Parses dropped non-image file as file attachment")
    func droppedTextFile() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("drop-\(UUID().uuidString).md")
            try "# Title".write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.writeObjects([url as NSURL])

            let result = FileDropLogic.parse(pasteboard: pb)
            #expect(result.files.count == 1)
            #expect(result.images.isEmpty)
            #expect(result.files[0].path == url.path)
        }
    }

    @Test("Parses raw PNG bytes from drag pasteboard")
    func droppedPNGBytes() {
        PasteboardIsolation.withExclusiveAccess {
            let image = NSImage(size: NSSize(width: 3, height: 3))
            image.lockFocus()
            NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 3, height: 3))
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("Failed to create PNG")
                return
            }

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.setData(png, forType: .png)

            let result = FileDropLogic.parse(pasteboard: pb)
            #expect(result.images.count == 1)
            #expect(!result.images[0].base64.isEmpty)
        }
    }

    @Test("Accepts drag when pasteboard has attachable content")
    func canAcceptDrag() throws {
        try PasteboardIsolation.withExclusiveAccess {
            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("drop-\(UUID().uuidString).pdf")
            try Data([0x25, 0x50, 0x44, 0x46]).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let pb = NSPasteboard(name: .drag)
            pb.clearContents()
            pb.writeObjects([url as NSURL])

            #expect(FileDropLogic.canAccept(pasteboard: pb))
        }
    }
}
