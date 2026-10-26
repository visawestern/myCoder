import Testing
import Foundation
@testable import myCoder

/// Live verification (localhost ollama only): the exact production image
/// path — MessagePartsBuilder.build with a real PNG off disk, through
/// DirectChatClient.send to a real vision model — must come back describing
/// the image. Opt-in via MYCODER_LIVE_TESTS=1 (needs `ollama serve` + a
/// vision model); skipped otherwise so normal runs stay hermetic.
/// Verified live 2026-10-15: "dark blue M shape with light blue circular
/// accents." (First cold run needs minutes for CPU model load.)
@Suite("LIVE image send via app stack (opt-in)")
struct LiveImageSendVerificationTests {

    @Test func visionModelSeesAttachedPng() async throws {
        guard ProcessInfo.processInfo.environment["MYCODER_LIVE_TESTS"] == "1" else {
            return // skipped: opt-in live test
        }
        let fm = FileManager.default
        let candidates = [
            RepoRoot.url.appendingPathComponent("myCoder/Sources/Resources/myCoderMark.png").path,
        ]
        guard let path = candidates.first(where: { fm.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            Issue.record("test image missing")
            return
        }
        let reachable: Bool = {
            guard let url = URL(string: "http://127.0.0.1:11434/api/tags"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return false }
            return models.contains { (($0["name"] as? String) ?? "").contains("gemma4") }
        }()
        guard reachable else {
            Issue.record("ollama vision model not running")
            return
        }
        let image = ClipboardImage(base64: data.base64EncodedString(), mimeType: "image/png")
        let parts = MessagePartsBuilder.build(text: "What shape and colors? One short sentence.",
                                              files: [], images: [image])
            .compactMap { part -> [String: Any]? in
                if part["type"] as? String == "text" {
                    return ["type": "text", "text": part["text"] as? String ?? ""]
                }
                if part["type"] as? String == "file",
                   let mime = part["mime"] as? String,
                   MessagePartsBuilder.isImageMimeType(mime),
                   let url = part["url"] as? String {
                    return ["type": "image_url", "image_url": ["url": url]]
                }
                return nil
            }
        let msgs = [DirectChatMessage(role: "user", content: "What shape and colors? One short sentence.", parts: parts)]
        // Vision inference on CPU under load can take minutes on first run;
        // use a generous timeout so the test measures correctness, not speed.
        let result = try await DirectChatClient.send(
            baseURL: "http://127.0.0.1:11434/v1", apiKey: nil,
            model: "speakeasy-gemma4-e2b-cpu:latest", messages: msgs,
            transport: URLSessionDirectChatTransport(timeout: 590))
        print("LIVE-IMAGE answer: \(result.content.prefix(200))")
        let lower = result.content.lowercased()
        #expect(lower.contains("m") && (lower.contains("dot") || lower.contains("blue") || lower.contains("circle") || lower.contains("dark")))
    }
}
