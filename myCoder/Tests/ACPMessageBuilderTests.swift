import Testing
import Foundation
@testable import myCoder

@Suite("ACP message builder — multimodal fix (plan Раздел 9 Блок 2)")
struct ACPMessageBuilderTests {

    @Test func textOnlyMessageHasStringContent() {
        let msg = ACPMessageBuilder.buildUserMessage(text: "hello", fileNames: [], images: [])
        let dict = msg.dictionary
        #expect(dict["role"] as? String == "user")
        // No images → content is a plain string, not an array
        #expect(dict["content"] is String)
        #expect((dict["content"] as? String)?.contains("hello") == true)
    }

    @Test func imagesProduceImageURLPartsNotPlaceholder() {
        let msg = ACPMessageBuilder.buildUserMessage(
            text: "describe this",
            fileNames: [],
            images: [(mimeType: "image/png", base64: "iVBORw0KG==")]
        )
        let dict = msg.dictionary
        // With images, content must be an array of parts
        let content = dict["content"] as? [[String: Any]]
        #expect(content != nil)
        // Must contain an image_url part with a data URL
        let imageParts = content?.filter { $0["type"] as? String == "image_url" }
        #expect(imageParts?.count == 1)
        let imageURL = (imageParts?.first?["image_url"] as? [String: Any])?["url"] as? String
        #expect(imageURL?.hasPrefix("data:image/png;base64,") == true)
        #expect(imageURL?.contains("iVBORw0KG") == true)
    }

    @Test func noPlaceholderTextForImages() {
        let msg = ACPMessageBuilder.buildUserMessage(
            text: "hi", fileNames: [], images: [(mimeType: "image/jpeg", base64: "/9j/4A==")]
        )
        let dict = msg.dictionary
        let content = dict["content"] as? [[String: Any]]
        // The old bug inserted "[1 image(s) attached]" as text — ensure that's gone
        for part in content ?? [] {
            if let text = part["text"] as? String {
                #expect(!text.contains("image(s) attached"))
            }
        }
    }

    @Test func filesAreListedAsTextPart() {
        let msg = ACPMessageBuilder.buildUserMessage(
            text: "review these", fileNames: ["foo.swift", "bar.swift"], images: []
        )
        // Files-only (no images) → content stays a plain string for compat
        let content = msg.dictionary["content"] as? String
        #expect(content?.contains("foo.swift") == true)
        #expect(content?.contains("bar.swift") == true)
        #expect(content?.contains("Attached files") == true)
    }

    @Test func multipleImagesEachGetOwnPart() {
        let msg = ACPMessageBuilder.buildUserMessage(
            text: "", fileNames: [],
            images: [("image/png", "aaa"), ("image/png", "bbb")]
        )
        let content = msg.dictionary["content"] as? [[String: Any]]
        let imageParts = content?.filter { $0["type"] as? String == "image_url" }
        #expect(imageParts?.count == 2)
    }

    @Test func textAndFilesAndImagesAllPresent() {
        let msg = ACPMessageBuilder.buildUserMessage(
            text: "explain", fileNames: ["readme.md"],
            images: [("image/png", "xxx")]
        )
        let content = msg.dictionary["content"] as? [[String: Any]]
        let textParts = content?.filter { $0["type"] as? String == "text" }
        let imageParts = content?.filter { $0["type"] as? String == "image_url" }
        #expect(textParts?.count == 1)
        #expect(imageParts?.count == 1)
        #expect((textParts?.first?["text"] as? String)?.contains("readme.md") == true)
    }
}
