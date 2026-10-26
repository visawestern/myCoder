import Testing
import Foundation
@testable import myCoder

/// E01 (FEATURE_TEST_REPORT): images/files were silently DROPPED on the
/// OpenAI-compatible send path (Ollama, OpenCode, Local Agent, custom OpenAI
/// providers) because `DirectChatMessage.content` was a plain String and the
/// builder never carried the real bytes. This is the same class of bug that
/// was fixed for ACP (Раздел 9 п.2) — now for the direct path (п.10(c)).
@Suite("E01 — multimodal attachments on OpenAI-compatible path")
struct E01MultimodalDirectChatTests {

    @Test("requestBody encodes image parts as OpenAI image_url content array")
    func requestBodyEncodesImages() throws {
        let msg = DirectChatMessage(
            role: "user",
            content: "what is this",
            parts: [
                ["type": "text", "text": "what is this"],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,AAAA"]]
            ]
        )
        let body = DirectChatClient.requestBody(model: "m", messages: [msg])
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"]
        #expect(content != nil)
        if let parts = content as? [[String: Any]] {
            #expect(parts.count == 2)
            #expect(parts[1]["type"] as? String == "image_url")
            let url = (parts[1]["image_url"] as? [String: Any])?["url"] as? String
            #expect(url?.hasPrefix("data:image/png;base64,") == true)
        } else {
            Issue.record("content should be an array of parts, got: \(String(describing: content))")
        }
    }

    @Test("requestBody keeps plain text messages as string content (backward compat)")
    func textOnlyStaysString() throws {
        let msg = DirectChatMessage(role: "user", content: "hello")
        let body = DirectChatClient.requestBody(model: "m", messages: [msg])
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages?.first?["content"] as? String == "hello")
    }

    @Test("ChatHistoryBuilder passes parts through for the new user message")
    func historyBuilderCarriesParts() throws {
        let imagePart: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,BBBB"]
        ]
        let msgs = ChatHistoryBuilder.messages(
            systemPrompt: nil,
            priorTurns: [],
            userText: "look at this",
            parts: [imagePart]
        )
        #expect(msgs.count == 1)
        let serialized = msgs[0].serializedContent()
        #expect(serialized is [[String: Any]])
        let parts = serialized as! [[String: Any]]
        #expect(parts.first(where: { $0["type"] as? String == "image_url" }) != nil)
    }

    @Test("DirectChatMessage builds image parts from ClipboardImage bytes")
    func buildsImagePartsFromClipboardImage() {
        let img = ClipboardImage(base64: "QUJD", mimeType: "image/png")
        let parts = DirectChatMessage.imageParts(for: img)
        #expect(parts.count == 1)
        let url = (parts[0]["image_url"] as? [String: Any])?["url"] as? String
        #expect(url == "data:image/png;base64,QUJD")
    }

    @Test("empty images produce no image parts")
    func emptyImageProducesNoParts() {
        let img = ClipboardImage(base64: "", mimeType: "image/png")
        #expect(DirectChatMessage.imageParts(for: img).isEmpty)
    }
}
