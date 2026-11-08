import Foundation

/// The internal model's verdict on whether a goal's plan is really done.
/// Produced by the devil's-advocate verification call.
struct GoalVerdict: Equatable, Sendable {
    var complete: Bool
    var notDone: [String]
    var reason: String
    var valid: Bool
}

enum GoalVerdictParser {

    /// Parse the model's JSON verdict. Accepts `{"complete": bool, "notDone": [...], "reason": "..."}`.
    /// Returns nil when the payload is not JSON (so the caller falls back to the
    /// deterministic plan check rather than trusting a broken answer).
    static func parse(_ json: String) -> GoalVerdict? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["complete"] is Bool else {
            return nil
        }
        let complete = obj["complete"] as? Bool ?? false
        let notDone = (obj["notDone"] as? [String]) ?? []
        let reason = (obj["reason"] as? String) ?? ""
        return GoalVerdict(complete: complete, notDone: notDone, reason: reason, valid: true)
    }

    /// Merge the model verdict with the deterministic plan check: the plan
    /// check is ground truth for completeness, and the model's reason adds
    /// the concrete "what is not done" detail when the plan is incomplete.
    ///
    /// Exception (live defect 2026-11-09): when the plan is EMPTY the host has
    /// no ground truth to judge against — the model worked directly, without
    /// maintaining todo_ steps. In that case a valid model verdict (complete:
    /// true) is trusted; otherwise the fallback continues the loop.
    static func merged(model: GoalVerdict?, plan: [UserGoal.PlanItem]) -> GoalVerdict {
        let deterministicComplete = GoalPlanStatusLogic.isComplete(plan)
        if let model, model.valid {
            if plan.isEmpty {
                return model
            }
            // The deterministic check decides completion; the model enriches the reason.
            let notDone = deterministicComplete ? [] : (model.notDone.isEmpty ? GoalPlanStatusLogic.notDoneItems(plan) : model.notDone)
            let reason = model.reason.isEmpty ? GoalPlanStatusLogic.notDoneReason(plan) : model.reason
            return GoalVerdict(complete: deterministicComplete, notDone: notDone, reason: reason, valid: true)
        }
        return GoalVerdict(complete: deterministicComplete,
                           notDone: GoalPlanStatusLogic.notDoneItems(plan),
                           reason: GoalPlanStatusLogic.notDoneReason(plan),
                           valid: true)
    }
}
