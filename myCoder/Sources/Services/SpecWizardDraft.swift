import Foundation

/// Ordered wizard phases. `ready` means the specification and its atomic
/// decomposition exist; it does not depend on any implementation work.
enum SpecWizardStep: String, Codable, CaseIterable {
    case setup
    case interview
    case specification
    case decomposition
    case ready

    var rank: Int {
        switch self {
        case .setup: return 0
        case .interview: return 1
        case .specification: return 2
        case .decomposition: return 3
        case .ready: return 4
        }
    }
}

/// Persisted state of the project spec wizard. Stored inside the project's own
/// database (`project_metadata`) so it travels with the project and survives
/// restarts. Long-form data (turns, revisions, nodes) lives in the dedicated
/// `spec_*` tables; this draft is the small, frequently written gate state.
struct SpecWizardDraft: Codable, Equatable {
    enum Status: String, Codable {
        case draft
        case forced
        case complete
    }

    var status: Status = .draft
    var goal: String = ""
    var stack: String = ""
    var constraints: String = ""
    var plannerModel: String = ""
    var coderModel: String = ""
    var interviewComplete: Bool = false
    var specVersion: Int = 0
    var decompositionNodeCount: Int = 0
    /// The step the user is looking at. Persisted, so a restart restores the
    /// exact position — including a deliberate return to an earlier step.
    /// `nil` in drafts written before this field existed.
    var activeStep: SpecWizardStep?
    var updatedAt: TimeInterval = 0

    init(status: Status = .draft,
         goal: String = "",
         stack: String = "",
         constraints: String = "",
         plannerModel: String = "",
         coderModel: String = "",
         interviewComplete: Bool = false,
         specVersion: Int = 0,
         decompositionNodeCount: Int = 0,
         activeStep: SpecWizardStep? = nil,
         updatedAt: TimeInterval = 0) {
        self.status = status
        self.goal = goal
        self.stack = stack
        self.constraints = constraints
        self.plannerModel = plannerModel
        self.coderModel = coderModel
        self.interviewComplete = interviewComplete
        self.specVersion = specVersion
        self.decompositionNodeCount = decompositionNodeCount
        self.activeStep = activeStep
        self.updatedAt = updatedAt
    }

    /// Forward-compatible decoding: drafts written before a field existed must
    /// keep opening. The gate state is too important to strand on a decode
    /// failure after an app update.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .draft
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        stack = try container.decodeIfPresent(String.self, forKey: .stack) ?? ""
        constraints = try container.decodeIfPresent(String.self, forKey: .constraints) ?? ""
        plannerModel = try container.decodeIfPresent(String.self, forKey: .plannerModel) ?? ""
        coderModel = try container.decodeIfPresent(String.self, forKey: .coderModel) ?? ""
        interviewComplete = try container.decodeIfPresent(Bool.self, forKey: .interviewComplete) ?? false
        specVersion = try container.decodeIfPresent(Int.self, forKey: .specVersion) ?? 0
        decompositionNodeCount = try container.decodeIfPresent(Int.self, forKey: .decompositionNodeCount) ?? 0
        activeStep = (try? container.decodeIfPresent(SpecWizardStep.self, forKey: .activeStep)) ?? nil
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
    }

    var hasModels: Bool {
        !plannerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !coderModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasBrief: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !stack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The furthest phase the stored data unlocks. Navigation never goes past
    /// it, so a stale position can neither skip a phase nor unlock chat.
    var furthestStep: SpecWizardStep {
        if status != .draft { return .ready }
        guard hasModels, hasBrief else { return .setup }
        guard interviewComplete else { return .interview }
        guard specVersion > 0 else { return .specification }
        guard decompositionNodeCount > 0 else { return .decomposition }
        return .ready
    }

    /// Where the wizard actually renders: the persisted position, clamped to
    /// what the data unlocks. A draft without a stored position opens at the
    /// furthest reached step (the behaviour before `activeStep` existed).
    var visibleStep: SpecWizardStep {
        let furthest = furthestStep
        guard let active = activeStep, active.rank <= furthest.rank else { return furthest }
        return active
    }

    /// Data-derived progress. Kept as the public "how far has this project
    /// got" value used by the checklist; the view uses `visibleStep`.
    var step: SpecWizardStep { furthestStep }

    var isEmpty: Bool {
        goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && constraints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Checklist shown on the right side of the wizard. Every item is driven by
/// real draft data or by an explicit implementation phase — nothing is faked.
enum SpecWizardChecklistLogic {
    enum ItemID: String, CaseIterable {
        case models
        case brief
        case interview
        case specification
        case decomposition
    }

    enum ItemState: Equatable {
        case done
        case pending
        case upcoming
    }

    struct Item: Identifiable, Equatable {
        let id: ItemID
        let state: ItemState
    }

    static func items(for draft: SpecWizardDraft) -> [Item] {
        let step = draft.step
        return [
            Item(id: .models, state: draft.hasModels ? .done : .pending),
            Item(id: .brief, state: draft.hasBrief ? .done : .pending),
            phaseItem(id: .interview,
                      done: draft.interviewComplete,
                      available: step.rank >= SpecWizardStep.interview.rank),
            phaseItem(id: .specification,
                      done: draft.specVersion > 0,
                      available: step.rank >= SpecWizardStep.specification.rank),
            phaseItem(id: .decomposition,
                      done: draft.decompositionNodeCount > 0,
                      available: step.rank >= SpecWizardStep.decomposition.rank)
        ]
    }

    private static func phaseItem(id: ItemID, done: Bool, available: Bool) -> Item {
        Item(id: id, state: done ? .done : (available ? .pending : .upcoming))
    }

    /// The step a checklist row opens. Model and brief rows share the setup
    /// step because they are edited on the same screen.
    static func step(for id: ItemID) -> SpecWizardStep {
        switch id {
        case .models, .brief: return .setup
        case .interview: return .interview
        case .specification: return .specification
        case .decomposition: return .decomposition
        }
    }

    /// A row is clickable as soon as its phase is reachable. Returning to a
    /// finished phase is allowed — that is the whole point of navigation.
    static func isNavigable(_ id: ItemID, in draft: SpecWizardDraft) -> Bool {
        items(for: draft).first(where: { $0.id == id })?.state != .upcoming
    }

    /// All five phases count. Upcoming phases contribute zero rather than
    /// being silently removed from the denominator (which made earlier
    /// progress jump to 100% before the spec existed).
    static func progress(for draft: SpecWizardDraft) -> Double {
        let all = items(for: draft)
        let done = all.filter { $0.state == .done }.count
        return Double(done) / Double(all.count)
    }

    static func canFinish(_ draft: SpecWizardDraft) -> Bool {
        items(for: draft).allSatisfy { $0.state == .done }
    }
}
