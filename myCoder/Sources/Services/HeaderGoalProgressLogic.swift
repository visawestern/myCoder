import Foundation

/// Pure header goal-checklist logic for roadmap item G: the top bar shows the
/// current session goal together with live `n/m` progress derived from the
/// agent's `currentSteps` (TodoWrite / markdown checklist / step markers).
/// Rendering lives in `TopBarView`; this enum owns the testable rules.
enum HeaderGoalProgressLogic {
    /// Badge text: goal plus `completed/total` when real steps exist.
    /// Falls back to the plain goal badge when there are no steps.
    static func badgeText(goal: String?, steps: [TaskStep], maxLength: Int = 40) -> String? {
        guard let goal, !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return steps.isEmpty ? nil : progressOnlyText(steps: steps)
        }
        let base = SessionGoalLogic.badgeLabel(for: SessionGoal(text: goal), maxLength: maxLength)
            ?? "🎯 \(goal)"
        guard !steps.isEmpty else { return base }
        return "\(base)  \(TaskProgress(steps: steps).formatted)"
    }

    /// Badge text when there is no goal string but steps exist.
    static func progressOnlyText(steps: [TaskStep]) -> String? {
        guard !steps.isEmpty else { return nil }
        return "🎯 \(TaskProgress(steps: steps).formatted)"
    }

    /// Header badge visibility: a session must exist, plus a goal or steps.
    static func shouldShow(selectedSession: ChatSession?, goal: String?, steps: [TaskStep]) -> Bool {
        guard selectedSession != nil else { return false }
        let hasGoal = !(goal?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasGoal || !steps.isEmpty
    }

    /// 0...1 fraction for a ProgressView; nil when there is nothing to show.
    static func progressFraction(steps: [TaskStep]) -> Double? {
        guard !steps.isEmpty else { return nil }
        return Double(TaskProgress(steps: steps).completedCount) / Double(steps.count)
    }

    /// SF Symbol per step status, shared with the right-panel progress list.
    static func stepIconName(for status: StepStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return RightPanelLayout.stepInProgressIcon
        case .waiting: return RightPanelLayout.stepWaitingIcon
        }
    }
}
