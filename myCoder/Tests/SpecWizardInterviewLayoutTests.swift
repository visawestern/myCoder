import Testing
import Foundation
@testable import myCoder

/// The interview screen keeps the live question above the history feed so the
/// answer controls are the first thing on screen, while the feed grows down —
/// oldest turn first, newest last.
@Suite("Spec wizard interview layout")
struct SpecWizardInterviewLayoutTests {

    @Test("The live question sits above the feed")
    func questionComesFirst() {
        let blocks = SpecWizardInterviewLayoutLogic.blocks(
            hasQuestion: true,
            isQuestionCardVisible: true,
            hasCompletedSummary: false,
            interviewComplete: false
        )
        #expect(blocks == [.question, .feed])
    }

    @Test("An answered question leaves the screen but stays in the feed")
    func answeredQuestionHidesButFeedRemains() {
        let blocks = SpecWizardInterviewLayoutLogic.blocks(
            hasQuestion: true,
            isQuestionCardVisible: false,
            hasCompletedSummary: false,
            interviewComplete: false
        )
        #expect(blocks == [.feed])
    }

    @Test("The completion summary takes the question slot")
    func summaryReplacesQuestion() {
        let blocks = SpecWizardInterviewLayoutLogic.blocks(
            hasQuestion: false,
            isQuestionCardVisible: false,
            hasCompletedSummary: true,
            interviewComplete: true
        )
        #expect(blocks == [.summary, .feed])
    }

    @Test("Before the first question only the feed shows")
    func feedOnlyOnFirstLoad() {
        let blocks = SpecWizardInterviewLayoutLogic.blocks(
            hasQuestion: false,
            isQuestionCardVisible: false,
            hasCompletedSummary: false,
            interviewComplete: false
        )
        #expect(blocks == [.feed])
    }

    @Test("A completed summary never hides the feed")
    func feedAlwaysLast() {
        let blocks = SpecWizardInterviewLayoutLogic.blocks(
            hasQuestion: true,
            isQuestionCardVisible: true,
            hasCompletedSummary: true,
            interviewComplete: true
        )
        #expect(blocks.last == .feed)
        #expect(!blocks.isEmpty)
    }
}
