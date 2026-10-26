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
        #expect(ContextWindowCatalog.limit(for: "totally-unknown") == 128_000)
    }

    @Test func badgeTextShowsPercentAndTokens() {
        let usage = ContextUsage(usedTokens: 54_000, limitTokens: 128_000)
        #expect(ContextUsageLogic.badgeText(usage) == "42%")
        #expect(ContextUsageLogic.detailText(usage).contains("54"))
        #expect(ContextUsageLogic.detailText(usage).contains("128"))
    }
}
