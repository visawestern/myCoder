import Testing
import Foundation
@testable import myCoder

/// The interview screen keeps the live question above the history feed so the
/// answer controls are the first thing on screen, while the feed lists the
/// answered exchanges newest first.
@Suite("Spec wizard interview layout")
struct SpecWizardInterviewLayoutTests {

    private func turn(_ role: String, _ content: String) -> SpecPlannerTurn {
        SpecPlannerTurn(role: role, content: content)
    }

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

    @Test("Newest exchange is first and each block keeps question then answer")
    func newestExchangeComesFirst() {
        let turns = [
            turn("planner", "Q1"),
            turn("user", "A1"),
            turn("planner", "Q2"),
            turn("user", "A2")
        ]
        let ordered = SpecWizardInterviewLayoutLogic.newestFirst(turns)
        #expect(ordered.map(\.content) == ["Q2", "A2", "Q1", "A1"])
    }

    @Test("The live question is not duplicated in the feed")
    func liveQuestionIsExcludedFromHistory() {
        let turns = [
            turn("planner", "Q1"),
            turn("user", "A1"),
            turn("planner", "Q2")
        ]
        let history = SpecWizardInterviewLayoutLogic.history(turns, excludingLiveQuestion: true)
        #expect(history.map(\.content) == ["Q1", "A1"])
        let ordered = SpecWizardInterviewLayoutLogic.newestFirst(history)
        #expect(ordered.map(\.content) == ["Q1", "A1"])
    }

    @Test("Excluding is a no-op when the question card is hidden")
    func historyKeepsEverythingWhileThinking() {
        let turns = [turn("planner", "Q1"), turn("user", "A1")]
        let history = SpecWizardInterviewLayoutLogic.history(turns, excludingLiveQuestion: false)
        #expect(history.count == 2)
    }
}
