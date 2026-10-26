import Testing
import Foundation
@testable import myCoder

/// WebSessionSummarizer: token estimation, progressive thresholds, and
/// summarized-seed construction for web-provider session restarts.
@Suite("WebSessionSummarizer — AI summary for session restarts")
struct WebSessionSummarizerTests {

    // MARK: - Token estimation

    @Test("Latin text estimates ~4 chars per token")
    func latinTokenEstimate() {
        // 40 latin chars -> ceil(40/4) = 10 tokens
        let text = String(repeating: "a", count: 40)
        #expect(WebSessionSummarizer.estimateTokens(in: text) == 10)
    }

    @Test("CJK text estimates ~2 chars per token")
    func cjkTokenEstimate() {
        // 10 CJK chars -> ceil(10/2) = 5 tokens
        let text = String(repeating: "中", count: 10)
        #expect(WebSessionSummarizer.estimateTokens(in: text) == 5)
    }

    @Test("Mixed text sums both scripts")
    func mixedTokenEstimate() {
        // 8 latin + 4 CJK -> ceil(8/4)=2 + ceil(4/2)=2 = 4 tokens
        let text = "abcdefgh" + String(repeating: "中", count: 4)
        #expect(WebSessionSummarizer.estimateTokens(in: text) == 4)
    }

    @Test("Empty text still returns at least 1 token")
    func emptyTokenEstimate() {
        #expect(WebSessionSummarizer.estimateTokens(in: "") >= 1)
    }

    @Test("Short text never returns zero")
    func shortTokenEstimate() {
        #expect(WebSessionSummarizer.estimateTokens(in: "a") >= 1)
    }

    @Test("Token estimate scales with length")
    func tokenEstimateScales() {
        let short = WebSessionSummarizer.estimateTokens(in: "hello world")
        let long = WebSessionSummarizer.estimateTokens(in: String(repeating: "hello world ", count: 100))
        #expect(long > short * 50)
    }

    // MARK: - Progressive thresholds

    @Test("Base threshold is 12k tokens (reachable: DOM transcript caps at ~25k)")
    func baseThreshold() {
        #expect(WebSessionSummarizer.maxTokensBeforeSummary(restartCount: 0) == 12_000)
    }

    @Test("Each restart grows the budget by 12k")
    func progressiveThresholds() {
        #expect(WebSessionSummarizer.maxTokensBeforeSummary(restartCount: 1) == 24_000)
        #expect(WebSessionSummarizer.maxTokensBeforeSummary(restartCount: 2) == 36_000)
    }

    // MARK: - Transcript bounding

    @Test("Short transcripts pass through untouched")
    func shortTranscriptUntouched() {
        let text = String(repeating: "a", count: 1000)
        #expect(WebSessionSummarizer.boundTranscript(text) == text)
    }

    @Test("Long transcripts keep head and tail with a gap marker")
    func longTranscriptBounded() {
        let text = String(repeating: "x", count: 30_000)
            + String(repeating: "y", count: 20_000)
            + String(repeating: "z", count: 30_000)
        let bounded = WebSessionSummarizer.boundTranscript(text)
        #expect(bounded.count <= WebSessionSummarizer.maxTranscriptChars + 100)
        #expect(bounded.hasPrefix(String(repeating: "x", count: 100)))
        #expect(bounded.hasSuffix(String(repeating: "z", count: 100)))
        #expect(bounded.contains("omitted for length"))
    }

    // MARK: - Summarized seed

    @Test("Seed includes preamble, goal, and summary")
    func seedIncludesAllParts() {
        let seed = WebSessionSummarizer.summarizedSeed(
            systemPreamble: "PREAMBLE",
            goal: "fix the parser",
            summary: "SUMMARY TEXT",
            restartCount: 0
        )
        #expect(seed.contains("PREAMBLE"))
        #expect(seed.contains("fix the parser"))
        #expect(seed.contains("SUMMARY TEXT"))
        #expect(seed.contains("Previous context summarized:"))
    }

    @Test("Later restarts number the session")
    func seedNumbersLaterRestarts() {
        let seed = WebSessionSummarizer.summarizedSeed(
            systemPreamble: "P",
            goal: nil,
            summary: "S",
            restartCount: 2
        )
        #expect(seed.contains("Session #3"))
    }

    @Test("Seed omits empty goal")
    func seedOmitsEmptyGoal() {
        let seed = WebSessionSummarizer.summarizedSeed(
            systemPreamble: "P",
            goal: nil,
            summary: "S",
            restartCount: 0
        )
        #expect(!seed.contains("Current goal:"))
    }

    @Test("Seed parts are separated by dividers")
    func seedUsesDividers() {
        let seed = WebSessionSummarizer.summarizedSeed(
            systemPreamble: "P",
            goal: "G",
            summary: "S",
            restartCount: 0
        )
        #expect(seed.contains("\n\n---\n\n"))
    }

    @Test("Seed orders continuation from the next step, not re-asking")
    func seedOrdersContinuation() {
        let seed = WebSessionSummarizer.summarizedSeed(
            systemPreamble: "P",
            goal: "G",
            summary: "S",
            restartCount: 0
        )
        #expect(seed.contains("Continue from the NEXT step"))
        #expect(seed.contains("Do not re-ask"))
    }
}
