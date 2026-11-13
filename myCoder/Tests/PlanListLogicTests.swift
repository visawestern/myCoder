import Testing
import Foundation
@testable import myCoder

/// Right-panel PLAN: at most ten rows are visible, longer plans scroll inside
/// a fixed viewport, and the list moves to the CURRENT step whenever the plan
/// advances (user directive 2026-11-13).
@Suite("Plan list — ten visible rows and current-step targeting")
struct PlanListLogicTests {

    private func step(_ title: String, _ status: StepStatus) -> TaskStep {
        TaskStep(title: title, status: status)
    }

    @Test("At most ten rows are visible")
    func visibleCountCapped() {
        #expect(PlanListLogic.visibleCount(total: 0) == 0)
        #expect(PlanListLogic.visibleCount(total: 4) == 4)
        #expect(PlanListLogic.visibleCount(total: 10) == 10)
        #expect(PlanListLogic.visibleCount(total: 11) == 10)
        #expect(PlanListLogic.visibleCount(total: 99) == 10)
    }

    @Test("The viewport height is fixed to the visible rows")
    func fixedHeight() {
        #expect(PlanListLogic.listHeight(total: 0, rowHeight: 42) == 0)
        #expect(PlanListLogic.listHeight(total: 3, rowHeight: 42) == 126)
        #expect(PlanListLogic.listHeight(total: 10, rowHeight: 42) == 420)
        #expect(PlanListLogic.listHeight(total: 40, rowHeight: 42) == 420)
    }

    @Test("Scrolling appears only above ten rows")
    func scrollOnlyWhenNeeded() {
        #expect(!PlanListLogic.shouldScroll(total: 0))
        #expect(!PlanListLogic.shouldScroll(total: 10))
        #expect(PlanListLogic.shouldScroll(total: 11))
    }

    @Test("The current step is the first in-progress step")
    func currentIsInProgress() {
        let steps = [
            step("done", .completed),
            step("working", .inProgress),
            step("next", .waiting),
            step("later", .inProgress),
        ]
        #expect(PlanListLogic.currentStepIndex(steps: steps) == 1)
    }

    @Test("Without an in-progress step the first waiting step is current")
    func currentFallsBackToWaiting() {
        let steps = [
            step("done", .completed),
            step("done too", .completed),
            step("next", .waiting),
            step("later", .waiting),
        ]
        #expect(PlanListLogic.currentStepIndex(steps: steps) == 2)
    }

    @Test("A fully completed plan points at its last step")
    func currentFallsBackToLastCompleted() {
        let steps = [
            step("one", .completed),
            step("two", .completed),
            step("three", .completed),
        ]
        #expect(PlanListLogic.currentStepIndex(steps: steps) == 2)
    }

    @Test("An empty plan has no current step")
    func emptyPlan() {
        #expect(PlanListLogic.currentStepIndex(steps: []) == nil)
        #expect(PlanListLogic.currentStepID(steps: []) == nil)
    }

    @Test("The current step id follows the resolved index")
    func currentStepID() {
        let steps = [
            step("done", .completed),
            step("working", .inProgress),
            step("next", .waiting),
        ]
        #expect(PlanListLogic.currentStepID(steps: steps) == steps[1].id)
    }
}
