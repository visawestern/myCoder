import Foundation

enum RightPanelLayout {
    static let changesIcon = "doc.text"
    static let branchIcon = "arrow.triangle.branch"
    static let commitIcon = "arrow.up.to.line.circle"
    static let panelMenuIcon = "ellipsis"
    static let panelExpandIcon = "arrow.up.left.and.arrow.down.right"
    static let branchChevronIcon = "chevron.down"
    static let commitMenuIcon = "ellipsis"

    static let stepInProgressIcon = "arrow.right"
    static let stepWaitingIcon = "circle"
    static let completedHeaderIcon = "chevron.up"
    static let waitingHeaderIcon = "chevron.down"

    static let subagentsIcon = "person.2"
    static let subagentRunningIcon = "arrow.right"
    static let subagentDoneIcon = "checkmark"
    static let subagentFailedIcon = "xmark"
}

enum RightPanelProgressDisplay {
    static let visibleWaitingLimit = 2

    static func completedSteps(_ steps: [TaskStep]) -> [TaskStep] {
        steps.filter { $0.status == .completed }
    }

    static func inProgressSteps(_ steps: [TaskStep]) -> [TaskStep] {
        steps.filter { $0.status == .inProgress }
    }

    static func waitingSteps(_ steps: [TaskStep]) -> [TaskStep] {
        steps.filter { $0.status == .waiting }
    }

    static func inlineWaitingSteps(_ steps: [TaskStep]) -> [TaskStep] {
        Array(waitingSteps(steps).prefix(visibleWaitingLimit))
    }

    static func collapsedWaitingCount(_ steps: [TaskStep]) -> Int {
        max(0, waitingSteps(steps).count - visibleWaitingLimit)
    }
}
