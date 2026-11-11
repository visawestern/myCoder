import Testing
import Foundation
@testable import myCoder

/// The core mechanic (user directive): a model's context window is picked up
/// automatically from the reference dictionary (opencode.json) by its exact
/// name — the same way opencode does. This proves the loader maps
/// `provider.<id>.models.<model>.limit.context` → model id, and that the
/// catalog consults that dictionary.
@MainActor
@Suite("OpenCode model-window reference dictionary")
struct OpenCodeModelWindowsTests {

    private func makeOpencodeJSON() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-windows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("opencode.json")
        let json = """
        {
          "provider": {
            "explabs": {
              "models": {
                "mercury-3": { "limit": { "context": 1000000, "output": 128000 } },
                "gpt-5": { "limit": { "context": 400000, "output": 128000 } },
                "claude-sonnet-5": { "limit": { "context": 1000000, "output": 128000 } },
                "no-limit-model": { "name": "no-limit-model" }
              }
            }
          }
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func loadsExactWindowsFromReferenceDictionary() throws {
        let url = try makeOpencodeJSON()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let windows = OpenCodeModelWindows.load(from: url.path)
        #expect(windows["mercury-3"]?.context == 1_000_000)
        #expect(windows["mercury-3"]?.output == 128_000)
        #expect(windows["gpt-5"]?.context == 400_000)
        #expect(windows["claude-sonnet-5"]?.context == 1_000_000)
        // A model without a limit is absent, never guessed.
        #expect(windows["no-limit-model"] == nil)
    }

    @Test func missingFileYieldsEmptyDictionary() {
        let windows = OpenCodeModelWindows.load(from: "/nonexistent/opencode.json")
        #expect(windows.isEmpty)
    }

    @Test func catalogUsesDictionaryAutomaticallyByExactName() throws {
        let url = try makeOpencodeJSON()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        ContextWindowCatalog.opencodeReferencePath = url.path
        defer { ContextWindowCatalog.opencodeReferencePath = ContextWindowCatalog.defaultOpencodePath }
        #expect(ContextWindowCatalog.limit(for: "mercury-3") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "gpt-5") == 400_000)
        #expect(ContextWindowCatalog.limit(for: "claude-sonnet-5") == 1_000_000)
        // Exact-only: a derivative name must not match.
        #expect(ContextWindowCatalog.limit(for: "gpt-5-codex") == ContextWindowCatalog.fallbackLimit)
    }
}
