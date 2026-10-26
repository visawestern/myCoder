import Testing
@testable import myCoder

@Suite("Message Display Images")
struct MessageDisplayImageTests {

    @Test("Does not duplicate images when parts and attachedImages both present")
    func deduplicatesAttachedImages() {
        let image = ClipboardImage(base64: "abc123", mimeType: "image/png")
        let message = Message(
            role: .user,
            content: "what is this",
            parts: [.text("what is this"), .image(base64: "abc123", mimeType: "image/png")],
            attachedImages: [image]
        )

        #expect(MessageDisplayLogic.hasImageParts(message))
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).isEmpty)
    }

    @Test("Shows legacy attachedImages when parts have no image")
    func legacyAttachedImagesFallback() {
        let image = ClipboardImage(base64: "abc123", mimeType: "image/png")
        let message = Message(role: .user, content: "", attachedImages: [image])

        #expect(!MessageDisplayLogic.hasImageParts(message))
        #expect(MessageDisplayLogic.attachedImagesForDisplay(message).count == 1)
    }
}
