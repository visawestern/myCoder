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

    enum CodingKeys: String, CodingKey {
        case id, title, plan, state, createdAt, updatedAt, lastError
        case isFinal, projectPath, chatID
    }

    /// Декодирование с обратной совместимостью: старые сохранённые цели
    /// (без ключа `isFinal`) читаются как обычные (`isFinal == false`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        plan = try c.decode([PlanItem].self, forKey: .plan)
        state = try c.decode(State.self, forKey: .state)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        isFinal = try c.decodeIfPresent(Bool.self, forKey: .isFinal) ?? false
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        chatID = try c.decodeIfPresent(String.self, forKey: .chatID)
    }

    let id: UUID
    var title: String
    var plan: [PlanItem]
    var state: State
    var createdAt: Date
    var updatedAt: Date
    var lastError: String?
    /// Итоговая цель проверки плана (создаётся автоматически после
    /// завершения обычной цели; по её завершению цель останавливается
    /// полностью). Отличает «проверочную» цель от обычной.
    var isFinal: Bool
    /// Project the goal belongs to. Nil for a chat-only goal (standalone
    /// chat) and for legacy goals created before binding existed.
    var projectPath: String?
    /// Chat the goal was created in. A chat-bound goal is visible only in
    /// that chat; nil means the goal belongs to the whole project.
    var chatID: String?

    init(id: UUID = UUID(),
         title: String,
         plan: [PlanItem] = [],
         state: State = .pending,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastError: String? = nil,
         isFinal: Bool = false,
         projectPath: String? = nil,
         chatID: String? = nil) {
        self.id = id
        self.title = title
        self.plan = plan
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastError = lastError
        self.isFinal = isFinal
        self.projectPath = projectPath
        self.chatID = chatID
    }
}
