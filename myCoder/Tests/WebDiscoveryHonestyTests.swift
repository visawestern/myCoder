import Testing
import Foundation
@testable import myCoder

/// Audit 2026-09-06 — web discovery honesty fixes:
/// 1. Chat sidebar chat-titles must NEVER parse as models (strict validator)
/// 2. Claude live menu labels (Fable/Opus/Sonnet/Haiku families)
/// 3. read_file on an image returns the ATTACHED_IMAGE marker (not a lie
///    about "model does not support image input") and round-trips through
///    the driver as a real attachment.
@Suite("Web discovery honesty + image attach (audit 2026-09-06)")
struct WebDiscoveryHonestyTests {

    // MARK: - ChatGPT strict label validation

    @Test func chatHistoryTitlesNeverParseAsChatGPTModels() {
        let v = WebChatVendor.chatgpt
        // Real sidebar titles scraped by the old broad scan (live evidence).
        #expect(!WebModelListParser.isValidModelLabel("Закрепить Лимиты ChatGPT Pro для кодинга", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Лимиты ChatGPT Pro для кодинга", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Открыть настройки диалога «Лимиты ChatGPT Pro для кодинга»", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Some long sentence about GPT models and how they work in projects", vendor: v))
        // Real model labels still pass.
        #expect(WebModelListParser.isValidModelLabel("GPT-5.2", vendor: v))
        #expect(WebModelListParser.isValidModelLabel("GPT-4o", vendor: v))
        #expect(WebModelListParser.isValidModelLabel("o3", vendor: v))
        // Bare "auto" is UI noise (effort/level chip), only the synthetic
        // fallback label "ChatGPT Auto" is a model.
        #expect(!WebModelListParser.isValidModelLabel("auto", vendor: v))
        #expect(WebModelListParser.isValidModelLabel("ChatGPT Auto", vendor: v))
    }

    @Test func chatGPTModeFallbackModelIsAccepted() {
        // The 2026 no-switcher fallback must survive WebProviderStore.sanitize.
        let v = WebChatVendor.chatgpt
        #expect(WebModelListParser.normalize("ChatGPT Auto", vendor: v) == "ChatGPT Auto")
    }

    // MARK: - Claude live menu labels

    @Test func claudeLiveMenuLabelsParse() {
        let v = WebChatVendor.claude
        // Live 2026 menu (probed via the embedded browser):
        for label in ["Fable 5.1", "Opus 5", "Sonnet 5", "Haiku 4.5", "Opus 4.8", "Sonnet 4.6"] {
            #expect(WebModelListParser.isValidModelLabel(label, vendor: v), "expected \(label) to parse")
        }
        // Menu chrome and prose are rejected.
        #expect(!WebModelListParser.isValidModelLabel("Effort", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Max", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Pro or Max", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("For your toughest challenges", vendor: v))
        #expect(!WebModelListParser.isValidModelLabel("Fable 5.1 is included in Max plans, or available with usage credits on Pro. Learn more", vendor: v))
    }

    // MARK: - ATTACHED_IMAGE protocol

    @Test func readFileOnImageReturnsAttachMarkerNotALie() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let png = dir + "/image.png"
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
        try bytes.write(to: URL(fileURLWithPath: png))

        let executor = ProjectWebToolExecutor(projectRoot: dir, accessLevel: .fullAccess)
        let result = await executor.execute(WebToolCall(name: "read_file", arguments: ["path": "image.png"]))

        #expect(result.hasPrefix("ATTACHED_IMAGE:image/png:"),
                "read_file on an image must return the attach marker, not the false 'model does not support image input'")

        let parsed = ProjectWebToolExecutor.parseAttachedImage(from: result)
        #expect(parsed?.mime == "image/png")
        #expect(parsed?.data == bytes)
    }

    @Test func parseAttachedImageRejectsGarbage() {
        #expect(ProjectWebToolExecutor.parseAttachedImage(from: "ok: wrote 5 chars") == nil)
        #expect(ProjectWebToolExecutor.parseAttachedImage(from: "ATTACHED_IMAGE:") == nil)
        #expect(ProjectWebToolExecutor.parseAttachedImage(from: "ATTACHED_IMAGE:image/png:!!!not-base64!!!") == nil)
    }

    @Test func svgReadsAsText() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svg-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "<svg><circle/></svg>".write(toFile: dir + "/icon.svg", atomically: true, encoding: .utf8)

        let executor = ProjectWebToolExecutor(projectRoot: dir, accessLevel: .fullAccess)
        let result = await executor.execute(WebToolCall(name: "read_file", arguments: ["path": "icon.svg"]))
        #expect(result.contains("<circle"), "SVG is text and must be read as text")
    }
}
