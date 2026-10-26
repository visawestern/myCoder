import Testing
@testable import myCoder

@Suite("OpenCode Zen provider")
struct OpenCodeZenCatalogTests {
    @Test("OpenCode Zen type uses hosted Zen endpoint")
    func providerTypeEndpoint() {
        #expect(ProviderType.openCodeZen.defaultURL == "https://opencode.ai/zen/v1")
        #expect(ProviderType.openCodeZen.endpointType == .openAI)
        #expect(ProviderType.openCodeZen.icon == "sparkles")
    }

    @Test("Anonymous catalog exposes temporary free models only")
    func anonymousFreeCatalog() {
        let result = OpenCodeZenCatalog.availableModels(
            from: ["big-pickle", "mimo-v2.5-free", "deepseek-v4-flash", "claude-opus-5"],
            apiKey: ""
        )

        #expect(result == ["big-pickle", "mimo-v2.5-free"])
    }

    @Test("Zen key enables only documented chat-compatible paid models")
    func keyEnabledCatalog() {
        let result = OpenCodeZenCatalog.availableModels(
            from: ["big-pickle", "deepseek-v4-flash", "gpt-5.5", "kimi-k2.7-code"],
            apiKey: "zen-key"
        )

        #expect(result == ["big-pickle", "deepseek-v4-flash", "kimi-k2.7-code"])
        #expect(!result.contains("gpt-5.5"))
    }

    @Test("repeated provider rows produce one model option each")
    func duplicateRowsAreCollapsed() {
        let result = OpenCodeZenCatalog.availableModels(
            from: ["big-pickle", "big-pickle", "mimo-v2.5-free", "mimo-v2.5-free"],
            apiKey: ""
        )
        #expect(result == ["big-pickle", "mimo-v2.5-free"])
    }
}
