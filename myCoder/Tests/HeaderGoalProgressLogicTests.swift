import Testing
@testable import myCoder

@Suite("G: header goal checklist progress")
struct HeaderGoalProgressLogicTests {
    private func step(_ title: String, _ status: StepStatus) -> TaskStep {
        TaskStep(title: title, status: status)
    }

    private func session() -> ChatSession {
        ChatSession(title: "t")
    }

    @Test func goalOnlyShowsPlainBadge() {
        #expect(HeaderGoalProgressLogic.badgeText(goal: "Ship it", steps: []) == "🎯 Ship it")
    }

    @Test func goalPlusStepsShowsCount() {
        let steps = [step("a", .completed), step("b", .inProgress), step("c", .waiting)]
        #expect(HeaderGoalProgressLogic.badgeText(goal: "Ship it", steps: steps) == "🎯 Ship it  1/3")
    }

    @Test func stepsWithoutGoalShowCountOnly() {
        let steps = [step("a", .completed), step("b", .waiting)]
        #expect(HeaderGoalProgressLogic.badgeText(goal: nil, steps: steps) == "🎯 1/2")
        #expect(HeaderGoalProgressLogic.badgeText(goal: "  ", steps: steps) == "🎯 1/2")
    }

    @Test func nothingShowsNothing() {
        #expect(HeaderGoalProgressLogic.badgeText(goal: nil, steps: []) == nil)
        #expect(HeaderGoalProgressLogic.badgeText(goal: "", steps: []) == nil)
    }

    @Test func visibilityNeedsSessionPlusGoalOrSteps() {
        let steps = [step("a", .waiting)]
        #expect(HeaderGoalProgressLogic.shouldShow(selectedSession: nil, goal: "g", steps: steps) == false)
        #expect(HeaderGoalProgressLogic.shouldShow(selectedSession: session(), goal: nil, steps: []) == false)
        #expect(HeaderGoalProgressLogic.shouldShow(selectedSession: session(), goal: "g", steps: []) == true)
        #expect(HeaderGoalProgressLogic.shouldShow(selectedSession: session(), goal: nil, steps: steps) == true)
    }

    @Test func fractionMatchesCompletedOverTotal() {
        let steps = [step("a", .completed), step("b", .completed), step("c", .waiting), step("d", .waiting)]
        #expect(HeaderGoalProgressLogic.progressFraction(steps: steps) == 0.5)
        #expect(HeaderGoalProgressLogic.progressFraction(steps: []) == nil)
    }

    @Test func stepIconsCoverAllStatuses() {
        #expect(HeaderGoalProgressLogic.stepIconName(for: .completed) == "checkmark.circle.fill")
        #expect(HeaderGoalProgressLogic.stepIconName(for: .inProgress) == RightPanelLayout.stepInProgressIcon)
        #expect(HeaderGoalProgressLogic.stepIconName(for: .waiting) == RightPanelLayout.stepWaitingIcon)
    }
}
