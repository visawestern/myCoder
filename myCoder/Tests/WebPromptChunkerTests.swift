import Testing
import Foundation
@testable import myCoder

@Suite("Web session limit + prompt chunking (plan Раздел 12 extension)")
struct WebPromptChunkerTests {

    // MARK: - Session limit detection

    @Test func detectsKimiLimitMessage() {
        let msg = "Your conversation with Kimi is getting too long. Try starting a new session."
        #expect(WebSessionLimitLogic.isSessionLimitReached(responseText: msg))
    }

    @Test func detectsGenericLimitMarkers() {
        #expect(WebSessionLimitLogic.isSessionLimitReached(responseText: "context length exceeded"))
        #expect(WebSessionLimitLogic.isSessionLimitReached(responseText: "会话过长，请开始新的对话"))
        #expect(!WebSessionLimitLogic.isSessionLimitReached(responseText: "Here is the answer."))
    }

    @Test func carryOverSeedIncludesPreambleGoalAndSummary() {
        let seed = WebSessionLimitLogic.carryOverSeed(
            systemPreamble: "PREAMBLE", goal: "ship v2", recentSummary: "did X and Y"
        )
        #expect(seed.contains("PREAMBLE"))
        #expect(seed.contains("ship v2"))
        #expect(seed.contains("did X and Y"))
    }

    @Test func carryOverSeedOmitsEmptyParts() {
        let seed = WebSessionLimitLogic.carryOverSeed(systemPreamble: "P", goal: nil, recentSummary: "")
        #expect(seed == "P")
    }

    // MARK: - Chunking

    @Test func smallPromptNotSplit() {
        let parts = WebPromptChunker.split("hello world", budget: 6000)
        #expect(parts.count == 1)
        #expect(parts.first == "hello world")
    }

    @Test func largePromptSplitOnParagraphs() {
        let para = String(repeating: "word ", count: 200)   // ~1000 chars
        let prompt = Array(repeating: para, count: 20).joined(separator: "\n\n")  // ~20k chars
        let parts = WebPromptChunker.split(prompt, budget: 5000)
        #expect(parts.count > 1)
        // Each part respects the budget (with small overhead tolerance).
        #expect(parts.allSatisfy { $0.count <= 5200 })
        // Reassembled content preserves all words.
        let joined = parts.joined(separator: "\n\n")
        #expect(joined.contains("word"))
    }

    @Test func codeFenceNotSplitMidBlock() {
        let code = "```swift\n" + Array(repeating: "let x = 1", count: 50).joined(separator: "\n") + "\n```"
        let prompt = "Intro paragraph.\n\n" + code + "\n\nOutro paragraph."
        let segments = WebPromptChunker.semanticSegments(prompt)
        // The whole fenced block is exactly one segment (never broken apart).
        let fenceSegs = segments.filter { $0.hasPrefix("```") }
        #expect(fenceSegs.count == 1)
        #expect(fenceSegs.first?.contains("let x = 1") == true)
        #expect(fenceSegs.first?.hasSuffix("```") == true)
    }

    @Test func oversizedSegmentHardSplitByLinesOnly() {
        let huge = Array(repeating: "a-line-of-text", count: 1000).joined(separator: "\n")
        let parts = WebPromptChunker.hardSplitByLines(huge, budget: 500)
        #expect(parts.count > 1)
        // No part starts or ends mid "a-line-of-text" token — each line is whole.
        for part in parts {
            for line in part.components(separatedBy: "\n") where !line.isEmpty {
                #expect(line == "a-line-of-text")
            }
        }
    }

    @Test func wrapForContinuationAddsHeaders() {
        let chunks = ["one", "two", "three"]
        let wrapped = WebPromptChunker.wrapForContinuation(chunks)
        #expect(wrapped.count == 3)
        #expect(wrapped[0].contains("PART 1/3"))
        #expect(wrapped[0].contains("do not answer yet"))
        #expect(wrapped[2].contains("FINAL PART 3/3"))
        #expect(wrapped[2].contains("may now respond"))
    }

    @Test func singleChunkNotWrapped() {
        let wrapped = WebPromptChunker.wrapForContinuation(["only"])
        #expect(wrapped == ["only"])   // no continuation headers for a single message
    }

    @Test func chunkedMessagesEndToEnd() {
        let big = Array(repeating: "Paragraph number here.", count: 500).joined(separator: "\n\n")
        let msgs = WebPromptChunker.chunkedMessages(big, budget: 4000)
        #expect(msgs.count > 1)
        #expect(msgs.first?.contains("PART 1/") == true)
        #expect(msgs.last?.contains("FINAL PART") == true)
    }
}
