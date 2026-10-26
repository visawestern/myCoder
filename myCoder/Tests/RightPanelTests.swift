import Testing
import Foundation
@testable import myCoder

// MARK: - RTP-01: Right Panel Visibility Logic

@Suite("RTP-01: Right panel visibility (showGoal)")
struct RightPanelVisibilityTests {

    private func isolatedDefaults(name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("showGoal defaults to false")
    func showGoalDefaultFalse() {
        let defaults = isolatedDefaults(name: "com.mycoder.tests.right-panel-default")
        let state = AppState(host: "127.0.0.1", port: 0, defaults: defaults)
        #expect(state.showGoal == false)
    }

    @Test("showGoal toggles to true")
    func showGoalToggleOn() {
        let defaults = isolatedDefaults(name: "com.mycoder.tests.right-panel-toggle-on")
        let state = AppState(host: "127.0.0.1", port: 0, defaults: defaults)
        state.showGoal = true
        #expect(state.showGoal == true)
    }

    @Test("showGoal toggles back to false")
    func showGoalToggleOff() {
        let defaults = isolatedDefaults(name: "com.mycoder.tests.right-panel-toggle-off")
        let state = AppState(host: "127.0.0.1", port: 0, defaults: defaults)
        state.showGoal = true
        state.showGoal = false
        #expect(state.showGoal == false)
    }

    @Test("showGoal is independent of showTerminal")
    func showGoalIndependentOfTerminal() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showGoal = true
        state.showTerminal = true
        #expect(state.showGoal == true)
        #expect(state.showTerminal == true)
    }

    @Test("startNewTask resets showGoal to false")
    func startNewTaskResetsShowGoal() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showGoal = true
        state.startNewTask()
        #expect(state.showGoal == false)
    }

    @Test("startNewTask resets currentSteps")
    func startNewTaskResetsSteps() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.currentSteps = [TaskStep(title: "Step 1", status: .inProgress)]
        state.startNewTask()
        #expect(state.currentSteps.isEmpty)
    }

    @Test("selectSession keeps the remembered panel state")
    func selectSessionKeepsShowGoal() {
        let state = AppState(host: "127.0.0.1", port: 0)
        state.showGoal = false
        let session = ChatSession(id: "s1", title: "Fix bug")
        state.selectSession(session)
        #expect(state.showGoal == false)

        let opened = AppState(host: "127.0.0.1", port: 0)
        opened.showGoal = true
        opened.selectSession(ChatSession(id: "s2", title: "Another"))
        #expect(opened.showGoal == true)
    }

    @Test("showGoal survives a new AppState instance")
    func showGoalIsPersisted() {
        let suiteName = "com.mycoder.tests.right-panel-state"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppState(host: "127.0.0.1", port: 0, defaults: defaults)
        first.showGoal = true
        #expect(defaults.bool(forKey: "com.mycoder.showGoal"))

        let restored = AppState(host: "127.0.0.1", port: 0, defaults: defaults)
        #expect(restored.showGoal == true)

        restored.showGoal = false
        #expect(defaults.bool(forKey: "com.mycoder.showGoal") == false)
    }

    @Test("RightPanelLayout icon constants are defined")
    func rightPanelLayoutIcons() {
        #expect(RightPanelLayout.changesIcon == "doc.text")
        #expect(RightPanelLayout.branchIcon == "arrow.triangle.branch")
        #expect(RightPanelLayout.commitIcon == "arrow.up.to.line.circle")
        #expect(RightPanelLayout.panelMenuIcon == "ellipsis")
        #expect(RightPanelLayout.panelExpandIcon == "arrow.up.left.and.arrow.down.right")
    }

    @Test("RightPanelLayout progress icon constants are defined")
    func rightPanelProgressIcons() {
        #expect(RightPanelLayout.stepInProgressIcon == "arrow.right")
        #expect(RightPanelLayout.stepWaitingIcon == "circle")
        #expect(RightPanelLayout.completedHeaderIcon == "chevron.up")
        #expect(RightPanelLayout.waitingHeaderIcon == "chevron.down")
    }
}

// MARK: - RTP-02: TaskStep Model

@Suite("RTP-02: TaskStep model")
struct TaskStepModelTests {

    @Test("TaskStep initializes with title and status")
    func taskStepInit() {
        let step = TaskStep(title: "Setup project", status: .inProgress)
        #expect(step.title == "Setup project")
        #expect(step.status == .inProgress)
    }

    @Test("TaskStep has unique identifier")
    func taskStepUniqueID() {
        let step1 = TaskStep(title: "Step 1", status: .waiting)
        let step2 = TaskStep(title: "Step 2", status: .waiting)
        #expect(step1.id != step2.id)
    }

    @Test("TaskStep is Identifiable")
    func taskStepIdentifiable() {
        let step = TaskStep(title: "test", status: .inProgress)
        #expect(!step.id.uuidString.isEmpty)
    }
}

// MARK: - StepStatus Enum

@Suite("StepStatus enum")
struct StepStatusTests {

    @Test("StepStatus has three cases")
    func stepStatusCaseCount() {
        let all: [StepStatus] = [.completed, .inProgress, .waiting]
        #expect(all.count == 3)
    }

    @Test("StepStatus.completed raw value")
    func stepStatusCompletedRawValue() {
        #expect(StepStatus.completed.rawValue == "completed")
    }

    @Test("StepStatus.inProgress raw value")
    func stepStatusInProgressRawValue() {
        #expect(StepStatus.inProgress.rawValue == "inProgress")
    }

    @Test("StepStatus.waiting raw value")
    func stepStatusWaitingRawValue() {
        #expect(StepStatus.waiting.rawValue == "waiting")
    }
}

// MARK: - TaskStep State Transitions

@Suite("TaskStep state transitions")
struct TaskStepTransitionTests {

    @Test("TaskStep transitions from inProgress to completed")
    func transitionInProgressToCompleted() {
        var step = TaskStep(title: "Step 1", status: .inProgress)
        step.status = .completed
        #expect(step.status == .completed)
    }

    @Test("TaskStep transitions from waiting to inProgress")
    func transitionWaitingToInProgress() {
        var step = TaskStep(title: "Step 2", status: .waiting)
        step.status = .inProgress
        #expect(step.status == .inProgress)
    }

    @Test("TaskStep transitions from completed back to inProgress")
    func transitionCompletedToInProgress() {
        var step = TaskStep(title: "Step 3", status: .completed)
        step.status = .inProgress
        #expect(step.status == .inProgress)
    }

    @Test("TaskStep title is immutable after init")
    func taskStepTitleImmutable() {
        let step = TaskStep(title: "Original", status: .waiting)
        #expect(step.title == "Original")
    }

    @Test("Multiple steps can transition independently")
    func multipleStepsTransitionIndependently() {
        var step1 = TaskStep(title: "Plan", status: .completed)
        var step2 = TaskStep(title: "Build", status: .inProgress)
        var step3 = TaskStep(title: "Test", status: .waiting)

        step1.status = .inProgress
        step2.status = .completed
        step3.status = .inProgress

        #expect(step1.status == .inProgress)
        #expect(step2.status == .completed)
        #expect(step3.status == .inProgress)
    }
}

// MARK: - TaskProgress Model

@Suite("TaskProgress model")
struct TaskProgressTests {

    @Test("TaskProgress computes completed count")
    func progressCompletedCount() {
        let steps = [
            TaskStep(title: "Step 1", status: .completed),
            TaskStep(title: "Step 2", status: .inProgress),
            TaskStep(title: "Step 3", status: .waiting)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.completedCount == 1)
    }

    @Test("TaskProgress computes waiting count")
    func progressWaitingCount() {
        let steps = [
            TaskStep(title: "Step 1", status: .completed),
            TaskStep(title: "Step 2", status: .waiting),
            TaskStep(title: "Step 3", status: .waiting)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.waitingCount == 2)
    }

    @Test("TaskProgress computes in-progress count")
    func progressInProgressCount() {
        let steps = [
            TaskStep(title: "Step 1", status: .inProgress),
            TaskStep(title: "Step 2", status: .inProgress)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.inProgressCount == 2)
    }

    @Test("TaskProgress total count")
    func progressTotalCount() {
        let steps = [
            TaskStep(title: "Step 1", status: .completed),
            TaskStep(title: "Step 2", status: .inProgress)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.totalCount == 2)
    }

    @Test("TaskProgress formatted string")
    func progressFormattedString() {
        let steps = [
            TaskStep(title: "Step 1", status: .completed),
            TaskStep(title: "Step 2", status: .inProgress),
            TaskStep(title: "Step 3", status: .waiting)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.formatted == "1/3")
    }

    @Test("TaskProgress with all completed")
    func progressAllCompleted() {
        let steps = (1...5).map { TaskStep(title: "Step \($0)", status: .completed) }
        let progress = TaskProgress(steps: steps)
        #expect(progress.completedCount == 5)
        #expect(progress.inProgressCount == 0)
        #expect(progress.waitingCount == 0)
        #expect(progress.formatted == "5/5")
    }

    @Test("TaskProgress with no steps")
    func progressEmpty() {
        let progress = TaskProgress(steps: [])
        #expect(progress.completedCount == 0)
        #expect(progress.inProgressCount == 0)
        #expect(progress.waitingCount == 0)
        #expect(progress.totalCount == 0)
        #expect(progress.formatted == "0/0")
    }
}

// MARK: - RightPanelProgressDisplay Logic

@Suite("RightPanelProgressDisplay logic")
struct RightPanelProgressDisplayTests {

    @Test("completedSteps filters correctly")
    func completedStepsFilter() {
        let steps = [
            TaskStep(title: "A", status: .completed),
            TaskStep(title: "B", status: .inProgress),
            TaskStep(title: "C", status: .completed)
        ]
        let completed = RightPanelProgressDisplay.completedSteps(steps)
        #expect(completed.count == 2)
        #expect(completed[0].title == "A")
        #expect(completed[1].title == "C")
    }

    @Test("inProgressSteps filters correctly")
    func inProgressStepsFilter() {
        let steps = [
            TaskStep(title: "A", status: .completed),
            TaskStep(title: "B", status: .inProgress),
            TaskStep(title: "C", status: .waiting)
        ]
        let inProgress = RightPanelProgressDisplay.inProgressSteps(steps)
        #expect(inProgress.count == 1)
        #expect(inProgress[0].title == "B")
    }

    @Test("waitingSteps filters correctly")
    func waitingStepsFilter() {
        let steps = [
            TaskStep(title: "A", status: .completed),
            TaskStep(title: "B", status: .inProgress),
            TaskStep(title: "C", status: .waiting),
            TaskStep(title: "D", status: .waiting)
        ]
        let waiting = RightPanelProgressDisplay.waitingSteps(steps)
        #expect(waiting.count == 2)
    }

    @Test("inlineWaitingSteps limits to visibleWaitingLimit")
    func inlineWaitingStepsLimit() {
        let steps = (1...5).map { TaskStep(title: "Step \($0)", status: .waiting) }
        let inline = RightPanelProgressDisplay.inlineWaitingSteps(steps)
        #expect(inline.count == RightPanelProgressDisplay.visibleWaitingLimit)
        #expect(inline.count == 2)
    }

    @Test("inlineWaitingSteps returns all when under limit")
    func inlineWaitingStepsUnderLimit() {
        let steps = [TaskStep(title: "Only", status: .waiting)]
        let inline = RightPanelProgressDisplay.inlineWaitingSteps(steps)
        #expect(inline.count == 1)
    }

    @Test("collapsedWaitingCount computes overflow beyond limit")
    func collapsedWaitingCountOverflow() {
        let steps = (1...5).map { TaskStep(title: "Step \($0)", status: .waiting) }
        let collapsed = RightPanelProgressDisplay.collapsedWaitingCount(steps)
        #expect(collapsed == 3) // 5 - 2 visible
    }

    @Test("collapsedWaitingCount returns 0 when under limit")
    func collapsedWaitingCountUnderLimit() {
        let steps = [TaskStep(title: "Only", status: .waiting)]
        let collapsed = RightPanelProgressDisplay.collapsedWaitingCount(steps)
        #expect(collapsed == 0)
    }

    @Test("collapsedWaitingCount returns 0 exactly at limit")
    func collapsedWaitingCountAtLimit() {
        let steps = [
            TaskStep(title: "A", status: .waiting),
            TaskStep(title: "B", status: .waiting)
        ]
        let collapsed = RightPanelProgressDisplay.collapsedWaitingCount(steps)
        #expect(collapsed == 0)
    }

    @Test("visibleWaitingLimit is 2")
    func visibleWaitingLimitValue() {
        #expect(RightPanelProgressDisplay.visibleWaitingLimit == 2)
    }
}

// MARK: - ExecutionStepSyncLogic
// Note: Additional ExecutionStepSyncLogic tests live in
// ExecutionStepSyncLogicTests.swift (already existing).
// The tests below verify complementary logic not covered there.

@Suite("ExecutionStepSyncLogic — additional")
struct ExecutionStepSyncLogicAdditionalTests {

    @Test("steps from single stepStart creates inProgress step")
    func stepsFromSingleStepStart() {
        let parts: [MessagePartContent] = [.stepStart]
        let steps = ExecutionStepSyncLogic.steps(from: parts)
        #expect(steps.count == 1)
        #expect(steps[0].status == .inProgress)
        #expect(steps[0].title == "Step 1")
    }

    @Test("steps ignores non-step content types")
    func stepsIgnoresOtherContent() {
        let parts: [MessagePartContent] = [
            .text("hello"),
            .reasoning("thinking..."),
            .toolCall(name: "read", args: "{}", result: nil, callID: nil)
        ]
        let steps = ExecutionStepSyncLogic.steps(from: parts)
        #expect(steps.isEmpty)
    }

    @Test("steps reuses existing step title when available")
    func stepsReusesExistingTitle() {
        let existing = [TaskStep(title: "Custom Step", status: .inProgress)]
        let parts: [MessagePartContent] = [.stepStart]
        let steps = ExecutionStepSyncLogic.steps(from: parts, existing: existing)
        #expect(steps.count == 1)
        #expect(steps[0].title == "Custom Step")
        #expect(steps[0].status == .inProgress)
    }

    @Test("mergedSteps returns incoming when non-empty")
    func mergedStepsReturnsIncoming() {
        let existing = [TaskStep(title: "Old", status: .completed)]
        let incoming = [TaskStep(title: "New", status: .inProgress)]
        let merged = ExecutionStepSyncLogic.mergedSteps(existing: existing, incoming: incoming)
        #expect(merged.count == 1)
        #expect(merged[0].title == "New")
    }

    @Test("mergedSteps returns existing when incoming is empty")
    func mergedStepsReturnsExistingWhenIncomingEmpty() {
        let existing = [TaskStep(title: "Keep", status: .inProgress)]
        let merged = ExecutionStepSyncLogic.mergedSteps(existing: existing, incoming: [])
        #expect(merged.count == 1)
        #expect(merged[0].title == "Keep")
    }

    @Test("mergedSteps handles both empty")
    func mergedStepsBothEmpty() {
        let merged = ExecutionStepSyncLogic.mergedSteps(existing: [], incoming: [])
        #expect(merged.isEmpty)
    }

    @Test("steps with finish only does nothing")
    func stepsOrphanedFinish() {
        let parts: [MessagePartContent] = [.stepFinish]
        let steps = ExecutionStepSyncLogic.steps(from: parts)
        #expect(steps.isEmpty)
    }
}
