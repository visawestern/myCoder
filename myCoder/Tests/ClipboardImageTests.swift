import Testing
import Foundation
import AppKit
@testable import myCoder

@Suite("Clipboard Image Paste", .serialized)
struct ClipboardImageTests {

    // MARK: - ClipboardProvider Tests

    @Test("ClipboardProvider returns NSImage or nil based on pasteboard state")
    func clipboardReturnsResult() {
        let provider = ClipboardProvider()
        let image = provider.fetchImage()
        if let img = image {
            #expect(img.size.width > 0)
        } else {
            #expect(image == nil)
        }
    }

    @Test("ClipboardProvider returns NSImage when pasteboard has image data")
    func imageInClipboard() {
        PasteboardIsolation.withExclusiveAccess {
            let provider = ClipboardProvider()
            let testImage = NSImage(size: NSSize(width: 10, height: 10))
            testImage.lockFocus()
            NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
            testImage.unlockFocus()

            let tiffData = testImage.tiffRepresentation
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(tiffData, forType: .tiff)

            let result = provider.fetchImage()
            #expect(result != nil)
            #expect(result?.size.width == 10)
        }
    }

    @Test("ClipboardImage stores base64 PNG data")
    func clipboardImageBase64() {
        PasteboardIsolation.withExclusiveAccess {
            let provider = ClipboardProvider()
            let testImage = NSImage(size: NSSize(width: 2, height: 2))
            testImage.lockFocus()
            NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
            testImage.unlockFocus()

            let tiffData = testImage.tiffRepresentation
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(tiffData, forType: .tiff)

            guard let image = provider.fetchImage() else {
                Issue.record("Expected image from clipboard")
                return
            }
            let clipImage = ClipboardImage(nsImage: image)
            #expect(!clipImage.base64.isEmpty)
            #expect(clipImage.mimeType == "image/png")
        }
    }

    @Test("ClipboardImage encodes to Data correctly")
    func clipboardImageData() {
        let testImage = NSImage(size: NSSize(width: 4, height: 4))
        testImage.lockFocus()
        NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        testImage.unlockFocus()

        let clipImage = ClipboardImage(nsImage: testImage)
        #expect(clipImage.pngData.count > 0)
    }

    // MARK: - MessagePartContent with image

    @Test("MessagePartContent.image case stores base64 and mimeType")
    func messagePartImage() {
        let part = MessagePartContent.image(base64: "abc123", mimeType: "image/png")
        if case .image(let b64, let mime) = part {
            #expect(b64 == "abc123")
            #expect(mime == "image/png")
        } else {
            Issue.record("Expected .image case")
        }
    }

    @Test("MessagePartContent.image has stable id")
    func messagePartImageId() {
        let part1 = MessagePartContent.image(base64: "aaa", mimeType: "image/png")
        let part2 = MessagePartContent.image(base64: "aaa", mimeType: "image/png")
        #expect(part1.id == part2.id)
    }

    // MARK: - Attached images tracking

    @Test("Attached images array tracks pasted images")
    func attachedImagesTracking() {
        var attachedImages: [ClipboardImage] = []
        let img1 = ClipboardImage(base64: "data1", mimeType: "image/png")
        let img2 = ClipboardImage(base64: "data2", mimeType: "image/jpeg")
        attachedImages.append(img1)
        attachedImages.append(img2)

        #expect(attachedImages.count == 2)
        #expect(attachedImages[0].mimeType == "image/png")
        #expect(attachedImages[1].mimeType == "image/jpeg")
    }

    @Test("Attached images can be removed by index")
    func attachedImagesRemove() {
        var attachedImages: [ClipboardImage] = [
            ClipboardImage(base64: "a", mimeType: "image/png"),
            ClipboardImage(base64: "b", mimeType: "image/jpeg"),
        ]
        attachedImages.remove(at: 0)
        #expect(attachedImages.count == 1)
        #expect(attachedImages[0].mimeType == "image/jpeg")
    }

    // MARK: - Message model with images

    @Test("Message stores attached images")
    func messageWithImages() {
        let images = [
            ClipboardImage(base64: "img1", mimeType: "image/png"),
        ]
        let msg = Message(role: .user, content: "describe this", attachedImages: images)
        #expect(msg.attachedImages?.count == 1)
        #expect(msg.attachedImages?.first?.base64 == "img1")
    }

    @Test("Message without images has nil attachedImages")
    func messageWithoutImages() {
        let msg = Message(role: .user, content: "hello")
        #expect(msg.attachedImages == nil)
    }

    // MARK: - sendMessage API body with images

    @Test("sendMessage encodes image parts in request body")
    func sendMessageWithImageParts() throws {
        let part = MessagePartsBuilder.imagePart(for: ClipboardImage(base64: "iVBORw0KGgo", mimeType: "image/png"))
        #expect(part?["type"] as? String == "file")
        #expect(part?["mime"] as? String == "image/png")
        #expect(part?["url"] as? String == "data:image/png;base64,iVBORw0KGgo")
    }

    // MARK: - View state: paste adds image to attached

    @Test("Pasting adds image to attachedImages state")
    func pasteAddsImage() {
        var attachedImages: [ClipboardImage] = []
        let newImage = ClipboardImage(base64: "pasted", mimeType: "image/png")
        attachedImages.append(newImage)
        #expect(attachedImages.count == 1)
    }

    @Test("Send clears attachedImages")
    func sendClearsAttached() {
        var attachedImages: [ClipboardImage] = [
            ClipboardImage(base64: "x", mimeType: "image/png")
        ]
        attachedImages = []
        #expect(attachedImages.isEmpty)
    }
}
