import Testing
import Foundation
@testable import myCoder

/// Context-window accounting: the user must see how full the model context is
/// before the provider silently truncates old turns, and auto-compaction must
/// fire on the same measurement.
@Suite("Context usage accounting")
struct ContextUsageLogicTests {

    @Test func estimatesLatinTextAtFourCharsPerToken() {
        #expect(ContextUsageLogic.estimateTokens("") == 0)
        #expect(ContextUsageLogic.estimateTokens("abcd") == 1)
        #expect(ContextUsageLogic.estimateTokens("hello world") == 3)
    }

    @Test func cjkCountsRoughlyOneTokenPerCharacter() {
        #expect(ContextUsageLogic.estimateTokens("你好世界") == 4)
        #expect(ContextUsageLogic.estimateTokens("你好 world") == 4)
    }

    @Test func messageOverheadAndPartsAreCounted() {
        let plain = Message(role: .user, content: "abcd", isFinished: true)
        let withTool = Message(
            role: .assistant,
            content: "abcd",
            parts: [.toolCall(name: "read_file", args: "{\"path\":\"a\"}", result: "contents", callID: "1")],
            isFinished: true
        )
        #expect(ContextUsageLogic.tokens(for: withTool) > ContextUsageLogic.tokens(for: plain))
    }

    @Test func usageRatioClampsAtOne() {
        let usage = ContextUsage(usedTokens: 300, limitTokens: 100)
        #expect(usage.ratio == 1)
        #expect(usage.percent == 100)
        #expect(usage.remainingTokens == 0)
    }

    @Test func shouldCompactAtNinetyPercent() {
        #expect(!ContextUsageLogic.shouldCompact(ContextUsage(usedTokens: 89, limitTokens: 100)))
        #expect(ContextUsageLogic.shouldCompact(ContextUsage(usedTokens: 90, limitTokens: 100)))
        #expect(ContextUsageLogic.shouldCompact(ContextUsage(usedTokens: 95, limitTokens: 100)))
    }

    @Test func reportedLimitWinsOverCatalog() {
        #expect(ContextWindowCatalog.limit(for: "unknown-model", reported: 7_000) == 7_000)
        #expect(ContextWindowCatalog.limit(for: "unknown-model", reported: 0) == ContextWindowCatalog.fallbackLimit)
    }

    @Test func catalogKnowsCommonFamilies() {
        #expect(ContextWindowCatalog.limit(for: "claude-sonnet-4") == 200_000)
        #expect(ContextWindowCatalog.limit(for: "gemini-2.5-pro") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "gpt-4o-mini") == 128_000)
        #expect(ContextWindowCatalog.limit(for: "qwen2.5-coder:32k") == 32_768)
        #expect(ContextWindowCatalog.limit(for: "llama3.1:8b-128k") == 131_072)
        // Unknown models use the configured default (user directive).
        #expect(ContextWindowCatalog.limit(for: "totally-unknown") == 200_000)
        #expect(ContextWindowCatalog.limit(for: "qwen3.8-27b-coder") == 200_000)
        #expect(ContextWindowCatalog.limit(for: "codegemma-7b") == 200_000)
    }

    // MARK: - opencode.json windows

    /// The user's `opencode.json` declares per-model context windows. myCoder
    /// must honour them when a model id matches exactly, so e.g. Mercury's 1M
    /// window is not collapsed to the 200k default.
    @Test func opencodeKnownModelsUseDeclaredWindow() {
        // Mercury: the user's example — must be 1M, not 200k default.
        #expect(ContextWindowCatalog.limit(for: "mercury-3") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "mercury-2") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "mercury") == 1_000_000)
        // Exact name matches from opencode.json.
        #expect(ContextWindowCatalog.limit(for: "gpt-5") == 400_000)
        #expect(ContextWindowCatalog.limit(for: "claude-sonnet-5") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "deepseek-v4-pro") == 1_048_576)
        #expect(ContextWindowCatalog.limit(for: "gemini-3.8-flash") == 1_048_576)
        #expect(ContextWindowCatalog.limit(for: "qwen3.7-max") == 1_000_000)
        #expect(ContextWindowCatalog.limit(for: "glm-5.2") == 1_048_576)
    }

    @Test func opencodeKnownModelsUseDeclaredOutput() {
        #expect(ContextWindowCatalog.outputLimit(for: "deepseek-v4-pro") == 393_216)
        #expect(ContextWindowCatalog.outputLimit(for: "claude-sonnet-5") == 128_000)
        #expect(ContextWindowCatalog.outputLimit(for: "gpt-5") == 128_000)
        #expect(ContextWindowCatalog.outputLimit(for: "gemini-3.8-flash") == 65_536)
    }

    /// A reported limit (live provider catalog) still wins over the opencode
    /// window — the opencode map is only the fallback for models the provider
    /// did not specify.
    @Test func reportedLimitStillWinsOverOpencodeWindow() {
        #expect(ContextWindowCatalog.limit(for: "gpt-5", reported: 99_000) == 99_000)
        #expect(ContextWindowCatalog.limit(for: "mercury-3", reported: 256_000) == 256_000)
    }

    /// Partial-match names must NOT trigger the opencode map — only exact ids do.
    @Test func opencodeMapRequiresExactId() {
        #expect(ContextWindowCatalog.limit(for: "gpt-5-codex") == 200_000)
        #expect(ContextWindowCatalog.limit(for: "qwen3.8-27b-coder") == 200_000)
        #expect(ContextWindowCatalog.limit(for: "claude-sonnet-5-x") == 200_000)
    }

    @Test func outputLimitDefaultsTo32k() {
        #expect(ContextWindowCatalog.outputLimit(for: "codegemma-7b") == 32_000)
        #expect(ContextWindowCatalog.outputLimit(for: "codegemma-7b", reported: 8_192) == 8_192)
        #expect(ContextWindowCatalog.outputLimit(for: "model-out16k") == 16_384)
    }

    @Test func badgeTextShowsPercentAndTokens() {
        let usage = ContextUsage(usedTokens: 54_000, limitTokens: 128_000)
        #expect(ContextUsageLogic.badgeText(usage) == "42%")
        #expect(ContextUsageLogic.detailText(usage).contains("54"))
        #expect(ContextUsageLogic.detailText(usage).contains("128"))
    }
}
