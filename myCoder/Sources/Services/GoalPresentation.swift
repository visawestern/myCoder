import Foundation

/// Colour role of a goal state. The UI maps this to the theme colours, so the
/// presentation rules stay testable without SwiftUI.
enum GoalStateColorRole: String, Equatable, Sendable {
    case brand
    case success
    case warning
    case error
    case muted
}

/// The single main transition offered for a goal, depending on its state.
enum GoalPrimaryAction: String, Equatable, Sendable {
    case start
    case pause
    case resume
    case none
}

/// Pure presentation model for the ЦЕЛЬ card in the right sidebar.
///
/// It owns the rules that decide what the card shows — status label, status
/// colour, progress, whether the plan spoiler or the "plan appears on start"
/// hint is shown, and which primary action button is offered — so those rules
/// can be verified without rendering SwiftUI.
struct GoalPresentation: Equatable, Sendable {
    let goal: UserGoal

    init(goal: UserGoal) {
        self.goal = goal
    }

    // MARK: - Status

    var stateLabel: AppLocalizationKey {
        switch goal.state {
        case .active: return .locGoalRunning
        case .paused: return .locGoalPaused
        case .done: return .locGoalDone
        case .error: return .locGoalError
        case .pending: return .locGoalCreated
        }
    }

    var stateColor: GoalStateColorRole {
        switch goal.state {
        case .active: return .brand
        case .done: return .success
        case .paused: return .warning
        case .error: return .error
        case .pending: return .muted
        }
    }

    // MARK: - Progress

    var doneCount: Int {
        goal.plan.filter { $0.status == .done }.count
    }

    var totalCount: Int {
        goal.plan.count
    }

    /// Fraction of completed plan steps (0…1). Empty plan means no progress.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(doneCount) / Double(totalCount)
    }

    var showsProgress: Bool {
        totalCount > 0
    }

    /// Without a plan there is nothing to expand — the card explains when the
    /// plan will appear instead of showing an empty spoiler.
    var showsPlanHint: Bool {
        !showsProgress
    }

    var showsPlanDisclosure: Bool {
        showsProgress
    }

    // MARK: - Actions

    var primaryAction: GoalPrimaryAction {
        switch goal.state {
        case .pending: return .start
        case .active: return .pause
        case .paused, .error: return .resume
        case .done: return .none
        }
    }

    /// Session controls of the composer goal row. Start is offered when the
    /// goal is not running, pause/stop only while it is running; a done goal
    /// can only be deleted.
    var canStart: Bool {
        goal.state == .pending || goal.state == .paused || goal.state == .error
    }

    var canPause: Bool {
        goal.state == .active
    }

    /// Stop is the hard version of pause: it also aborts the running turn.
    var canStop: Bool {
        goal.state == .active
    }

    /// A goal is complete when it is marked done or every plan step is done.
    var isComplete: Bool {
        goal.state == .done || (showsProgress && doneCount == totalCount)
    }
}
