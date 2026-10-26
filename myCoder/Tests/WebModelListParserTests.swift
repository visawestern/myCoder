import Testing
@testable import myCoder

@Suite("Web model list parser (plan Раздел 13 п.4)")
struct WebModelListParserTests {

    @Test func parsesNewlineSeparatedModels() {
        let text = "k2\nk2-thinking\nk1.5"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .kimi)
        #expect(models == ["k2", "k2-thinking", "k1.5"])
    }

    @Test func stripsSelectionMarkersAndDedupes() {
        let text = "✓ gpt-4o\ngpt-4o\ngpt-4.1"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .chatgpt)
        #expect(models == ["gpt-4o", "gpt-4.1"])
    }

    @Test func filtersChatGPTFeatureActionsFromModels() {
        let text = "ChatGPT\nGPT-5\nDeep Research\nCreate image\nCanvas\no3"
        #expect(WebModelListParser.parse(dropdownText: text, vendor: .chatgpt) == ["GPT-5", "o3"])
    }

    @Test func dropsUINoiseEntries() {
        let text = "qwen-max\nUpgrade\nNew\nqwen2.5-coder\nSettings"
        let models = WebModelListParser.parse(dropdownText: text, vendor: .qwen)
        #expect(models == ["qwen-max", "qwen2.5-coder"])
    }

    @Test func normalizeRejectsChrome() {
        #expect(WebModelListParser.normalize("", vendor: .kimi) == nil)
        #expect(WebModelListParser.normalize("New", vendor: .kimi) == nil)
        #expect(WebModelListParser.normalize("✓ k2", vendor: .kimi) == "k2")
        #expect(WebModelListParser.normalize(String(repeating: "x", count: 80), vendor: .kimi) == nil)
    }

    @Test func updatedSetsDiscoveredModels() {
        let cfg = WebProviderConfig(vendor: .kimi)
        let updated = WebModelListParser.updated(cfg, withDropdownText: "k2\nk2-thinking")
        #expect(updated.discoveredModels.map { $0.name } == ["k2", "k2-thinking"])
        // And connectivity now returns the real models over defaults.
        #expect(WebProviderConnectivity.models(for: updated) == ["k2", "k2-thinking"])
    }

    @Test func updatedKeepsDefaultsWhenParseEmpty() {
        let cfg = WebProviderConfig(vendor: .kimi)
        let updated = WebModelListParser.updated(cfg, withDropdownText: "New\nUpgrade")
        #expect(updated.discoveredModels.isEmpty)  // nothing real parsed
    }

    @Test func emptyRefreshAnnotatesStaleChatGPTModels() {
        let cfg = WebProviderConfig(
            vendor: .chatgpt,
            selectedModel: "gpt-stale",
            discoveredModels: [WebProviderModel(name: "gpt-stale")]
        )
        // Merge semantics (audit 2026-09-06): a scan that yields nothing
        // real ANNOTATES the previously known model instead of destroying it
        // (the vendor menu is context-dependent).
        let updated = WebModelListParser.updated(cfg, withDropdownText: "ChatGPT\nDeep Research\nCanvas")
        #expect(updated.discoveredModels.count == 1)
        #expect(updated.discoveredModels[0].discoveryMessage?.contains("context-dependent") == true)
        #expect(updated.selectedModel == "gpt-stale")
    }

    @Test func pipeAndCommaSeparators() {
        let models = WebModelListParser.parse(dropdownText: "model-a1 | model-b2, model-c3", vendor: .custom)
        #expect(models == ["model-a1", "model-b2", "model-c3"])
    }
}

@Suite("ChatGPT synthetic fallback labels survive sanitize (audit 2026-09-08)")
struct ChatGPTFallbackLabelTests {
    @Test func autoReasoningLabelIsValid() {
        #expect(WebModelListParser.normalize("ChatGPT Auto (Reasoning)", vendor: .chatgpt) == "ChatGPT Auto (Reasoning)")
    }

    @Test func autoInstantLabelIsValid() {
        #expect(WebModelListParser.normalize("ChatGPT Auto (Instant)", vendor: .chatgpt) == "ChatGPT Auto (Instant)")
    }

    @Test func plainAutoStillValid() {
        #expect(WebModelListParser.normalize("ChatGPT Auto", vendor: .chatgpt) == "ChatGPT Auto")
    }
}
