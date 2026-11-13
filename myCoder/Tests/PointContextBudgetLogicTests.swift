import Foundation
import Testing
@testable import myCoder

/// TDD for plan item 9: the point-context prompt must fit the model's FULL
/// context window, never the remaining window. Every send already carries the
/// point context, and stale context is inside it — so the budget is computed
/// from the full window minus the fixed parts of THIS packet (system prompt,
/// request), and the used-up chat volume is NOT subtracted again.
@Suite("Point-context budget — full-window bound")
struct PointContextBudgetLogicTests {

    @Test("Evidence budget = half-window minus fixed parts, no used-volume subtraction")
    func evidenceBudgetUsesFullWindow() {
        // The signature has no "usedTokens" input on purpose: what was already
        // consumed by the chat must not shrink this packet's budget.
        // Target is HALF the full window (room for the answer).
        #expect(PointContextBudgetLogic.contentTargetTokens(fullLimit: 100_000) == 50_000)
        let budget = PointContextBudgetLogic.remainingForContent(fullLimit: 100_000, systemTokens: 20_000)
        #expect(budget == 30_000)
        #expect(PointContextBudgetLogic.remainingForContent(fullLimit: 100_000, systemTokens: 0) == 50_000)
        #expect(PointContextBudgetLogic.remainingForContent(fullLimit: 10_000, systemTokens: 99_000) == 0)
    }

    @Test("Exact limit fits, limit+1 does not")
    func exactBoundary() {
        #expect(PointContextBudgetLogic.fits(fullLimit: 100_000, systemTokens: 10_000, contentTokens: 90_000))
        #expect(!PointContextBudgetLogic.fits(fullLimit: 100_000, systemTokens: 10_000, contentTokens: 90_001))
    }

    @Test("Packet estimate includes system, request and evidence")
    func packetEstimateParts() {
        let estimate = PointContextBudgetLogic.estimatedPacketTokens(
            systemPrompt: "You are a helper.",
            request: "Fix the bug",
            evidenceText: "```\nlet x = 1\n```",
            historyText: "История чата."
        )
        #expect(estimate > 0)
        // Evidence-only estimate must be smaller than the full packet.
        let less = PointContextBudgetLogic.estimatedPacketTokens(
            systemPrompt: nil, request: "Fix", evidenceText: "x", historyText: ""
        )
        #expect(less < estimate)
    }

    @Test("Truncation decision respects the full window")
    func truncationDecision() {
        // request+system alone fill the window → no evidence budget.
        let budget = PointContextBudgetLogic.remainingForContent(fullLimit: 1_000, systemTokens: 1_000)
        #expect(budget == 0)
        #expect(PointContextBudgetLogic.shouldDropEvidence(fullLimit: 1_000, systemTokens: 1_000))
        #expect(!PointContextBudgetLogic.shouldDropEvidence(fullLimit: 10_000, systemTokens: 1_000))
    }

    @Test("System prompt token estimate reuses the shared estimator")
    func systemTokenEstimate() {
        let system = "System instruction for the coding agent."
        #expect(PointContextBudgetLogic.systemTokens(system) == ContextUsageLogic.estimateTokens(system))
        #expect(PointContextBudgetLogic.systemTokens(nil) == 0)
    }
}
