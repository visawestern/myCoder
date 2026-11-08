import Foundation

/// Deterministic judgment about a goal's plan. This is the host-side ground
/// truth the internal model's verdict is checked against: a plan is complete
/// only when every step is `done`; anything else is listed as not-done so the
/// continuation prompt can name exactly what remains.
enum GoalPlanStatusLogic {

    /// A plan is "ready to run" when it has at least one concrete step. An
    /// empty plan means the model has not decomposed the goal yet — the host
    /// asks it to build the plan first.
    static func ready(_ plan: [UserGoal.PlanItem]) -> Bool {
        !plan.isEmpty
    }

    /// True when every step is done.
    static func isComplete(_ plan: [UserGoal.PlanItem]) -> Bool {
        !plan.isEmpty && plan.allSatisfy { $0.status == .done }
    }

    /// Titles of steps that are NOT done (including blocked/in-progress/todo).
    static func notDoneItems(_ plan: [UserGoal.PlanItem]) -> [String] {
        plan.filter { $0.status != .done }.map(\.title)
    }

    /// Short reason string used in the continuation prompt / status line.
    static func notDoneReason(_ plan: [UserGoal.PlanItem]) -> String {
        let items = notDoneItems(plan)
        guard !items.isEmpty else { return "" }
        return items.joined(separator: "; ")
    }
}
