import Foundation
import CoreGraphics

/// Sizing and current-step rules for the right-panel PLAN list.
///
/// Input: the ordered plan steps. Output: how many rows fit (max ten), the
/// exact scroll-viewport height, and which step the list must reveal when the
/// plan advances.
///
/// Dependencies: CoreGraphics for CGFloat only. Pure, no UI, no AppState.
enum PlanListLogic {
    /// User directive 2026-11-13: never show more than ten plan rows; the
    /// rest live in a fixed-height scroll list that follows the current step.
    static let maxVisibleRows = 10

    /// One row has a fixed height so ten rows always occupy the same space,
    /// even when a title wraps (titles are capped at two lines).
    static let rowHeight: CGFloat = 42

    /// Number of rows to reserve height for.
    ///
    /// - Parameter total: all plan steps.
    /// - Returns: 0…10.
    static func visibleCount(total: Int) -> Int {
        min(max(0, total), maxVisibleRows)
    }

    /// Exact height of the plan viewport.
    ///
    /// - Parameters:
    ///   - total: all plan steps.
    ///   - rowHeight: fixed row height (injectable for tests).
    /// - Returns: `visibleCount × rowHeight`, 0 when empty.
    static func listHeight(total: Int, rowHeight: CGFloat = PlanListLogic.rowHeight) -> CGFloat {
        CGFloat(visibleCount(total: total)) * rowHeight
    }

    /// Whether the plan needs its own scrollbar.
    ///
    /// - Parameter total: all plan steps.
    /// - Returns: true when more than ten rows exist.
    static func shouldScroll(total: Int) -> Bool {
        total > maxVisibleRows
    }

    /// Index of the step the list should center on.
    ///
    /// Rules:
    /// 1. the first `inProgress` step — that is what the model is doing now;
    /// 2. otherwise the first `waiting` step — what happens next;
    /// 3. otherwise the last `completed` step — a finished plan stays at its
    ///    end instead of jumping back to the top;
    /// 4. empty plan — nil.
    ///
    /// - Parameter steps: ordered plan steps.
    /// - Returns: 0-based index, or nil when the plan is empty.
    static func currentStepIndex(steps: [TaskStep]) -> Int? {
        if let index = steps.firstIndex(where: { $0.status == .inProgress }) {
            return index
        }
        if let index = steps.firstIndex(where: { $0.status == .waiting }) {
            return index
        }
        return steps.isEmpty ? nil : steps.count - 1
    }

    /// Stable id of the current step, for `ScrollViewProxy.scrollTo`.
    ///
    /// - Parameter steps: ordered plan steps.
    /// - Returns: the current step's id, or nil when the plan is empty.
    static func currentStepID(steps: [TaskStep]) -> TaskStep.ID? {
        guard let index = currentStepIndex(steps: steps) else { return nil }
        return steps[index].id
    }
}
