import Testing
import Foundation
@testable import myCoder

/// Harness-tax C4 living gate: the minimal profile must stay substantially
/// cheaper than full, and the numbers below are the measured baseline
/// (also recorded in .claude/evals/harness-tax-report.md).
@Suite("Harness-tax C4 measurement gate")
struct HarnessTaxMeasureTests {

    @Test func preambleTaxRatios() {
        let full = WebToolProtocolEmulator.systemPreamble(profile: .full)
        let standard = WebToolProtocolEmulator.systemPreamble(profile: .standard)
        let minimal = WebToolProtocolEmulator.systemPreamble(profile: .minimal)
        print("HARNESS-TAX full=\(full.utf8.count)B standard=\(standard.utf8.count)B minimal=\(minimal.utf8.count)B")
        // Minimal must stay under 65% of full initial context. Floor analysis
        // (C4): everything left in minimal is live-proven — the concrete
        // example fixes model refusals (audit 2026-09-09), the XML form is
        // emitted natively by some vendors, the cwd/date line is env context.
        // Cutting below 0.64 means cutting guards, not fat. Bigger wins live
        // in history budget + idle-killer + model split, not here.
        #expect(Double(minimal.utf8.count) / Double(full.utf8.count) < 0.65)
        // Standard sits between the two.
        #expect(standard.utf8.count > minimal.utf8.count)
        #expect(standard.utf8.count < full.utf8.count)
    }

    @Test func historyCapBoundsContext() {
        let sys = String(repeating: "s", count: 500)
        let prior = (0..<50).map { ChatHistoryBuilder.Turn(role: "user", content: "turn \($0) " + String(repeating: "w", count: 100), isFinished: true) }
        let capped50 = ChatHistoryBuilder.contextBytes(systemPrompt: sys, priorTurns: prior, userText: "go")
        let capped20 = ChatHistoryBuilder.contextBytes(systemPrompt: sys, priorTurns: Array(prior.suffix(20)), userText: "go")
        print("HARNESS-TAX history 50turns=\(capped50)B suffix20=\(capped20)B")
        // The 20-turn cap holds: 50 turns in cost the same as the last 20.
        #expect(capped50 == capped20)
        // …and the cap is real: fewer turns cost less.
        let capped5 = ChatHistoryBuilder.contextBytes(systemPrompt: sys, priorTurns: Array(prior.suffix(5)), userText: "go")
        #expect(capped5 < capped20)
    }
}
