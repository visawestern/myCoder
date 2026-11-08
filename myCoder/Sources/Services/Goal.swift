import Foundation

/// A user goal (ЦЕЛЬ) with a plan of atomic steps. The model maintains the plan
/// via `todo_` tools; the host verifies progress after each completed turn and
/// can auto-continue with «продолжай по плану, обнови прогресс».
///
/// Named `UserGoal` because `Goal` already exists in `Task.swift` for the task
/// wizard's decomposition.
struct UserGoal: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Created, plan not yet confirmed ready.
        case pending
        /// Running; the host verifies each turn and auto-continues.
        case active
        /// Paused by the user (e.g. after an error that repeated retries did
        /// not clear). No auto-continue while paused.
        case paused
        /// The model returned an error even after retries; needs user action.
        case error
        /// Every plan step is done.
        case done
    }

    struct PlanItem: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable {
            case todo
            case inProgress = "in_progress"
            case done
            case blocked
        }
        var title: String
        var status: Status
        var note: String?
    }

    let id: UUID
    var title: String
    var plan: [PlanItem]
    var state: State
    var createdAt: Date
    var updatedAt: Date
    var lastError: String?

    init(id: UUID = UUID(),
         title: String,
         plan: [PlanItem] = [],
         state: State = .pending,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastError: String? = nil) {
        self.id = id
        self.title = title
        self.plan = plan
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastError = lastError
    }
}
