import SwiftUI
import Foundation

/// Right-panel «ЦЕЛЬ» section: the active goal, its plan, and lifecycle
/// controls (start / pause / resume / delete). Reads and writes the disk-backed
/// GoalStore (`~/.mycoder/goals.json`), so it always reflects the same data
/// the `/goal` command and auto-verification use.
struct GoalsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var goals: [UserGoal] = []
    @State private var expandedGoalID: UUID?

    private var language: AppLanguage { appState.appLanguage }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var title: String {
        language == .russian ? "ЦЕЛЬ" : "GOAL"
    }

    private var emptyMessage: String {
        language == .russian ? "Нет цели. Задай через /goal <текст>" : "No goal. Set one via /goal <text>"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }

            if goals.isEmpty {
                Text(emptyMessage)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(goals) { goal in
                    GoalRow(
                        goal: goal,
                        expanded: expandedGoalID == goal.id,
                        language: language,
                        onToggle: {
                            withAnimation {
                                expandedGoalID = expandedGoalID == goal.id ? nil : goal.id
                            }
                        },
                        onAction: { action in apply(action, to: goal) }
                    )
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .init("myCoderGoalStoreChanged"))) { _ in
            reload()
        }
    }

    private func reload() {
        goals = GoalStore.load(homeDirectory: home)
    }

    private func apply(_ action: GoalRow.Action, to goal: UserGoal) {
        switch action {
        case .start:
            _ = try? GoalStore.setState(id: goal.id, state: .active, homeDirectory: home)
        case .pause:
            _ = try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: home)
        case .resume:
            _ = try? GoalStore.setState(id: goal.id, state: .active, homeDirectory: home)
        case .delete:
            _ = try? GoalStore.remove(id: goal.id, homeDirectory: home)
        }
        withAnimation { reload() }
    }
}

/// One goal row: status + title + progress, a tappable plan spoiler, and
/// lifecycle buttons that depend on the goal's state.
struct GoalRow: View {
    enum Action {
        case start, pause, resume, delete
    }

    let goal: UserGoal
    let expanded: Bool
    let language: AppLanguage
    let onToggle: () -> Void
    let onAction: (Action) -> Void

    private var stateLabel: String {
        switch goal.state {
        case .active: return language == .russian ? "выполняется" : "active"
        case .paused: return language == .russian ? "пауза" : "paused"
        case .done: return language == .russian ? "готово" : "done"
        case .error: return language == .russian ? "ошибка" : "error"
        case .pending: return language == .russian ? "создана" : "pending"
        }
    }

    private var stateColor: Color {
        switch goal.state {
        case .active: return Color.mimo.success
        case .done: return Color.mimo.success
        case .paused, .error: return Color.mimo.error
        case .pending: return Color.mimo.textMuted
        }
    }

    private var doneCount: Int {
        goal.plan.filter { $0.status == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(goal.title)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(stateLabel)
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            if !goal.plan.isEmpty {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                        Text("\(doneCount)/\(goal.plan.count)")
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.textSecondary)
                        Spacer()
                    }
                }
                .buttonStyle(HandCursorButtonStyle())

                if expanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(goal.plan.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 6) {
                                Image(systemName: statusIcon(for: item.status))
                                    .interfaceFont(size: 10)
                                    .foregroundColor(statusColor(for: item.status))
                                Text(item.title)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.leading, 10)
                }
            }

            HStack(spacing: 6) {
                switch goal.state {
                case .pending, .done, .error, .paused:
                    if goal.state == .pending {
                        controlButton("play.fill", .start)
                    }
                    if goal.state == .paused || goal.state == .error {
                        controlButton("arrow.clockwise", .resume)
                        controlButton("trash", .delete)
                    }
                    if goal.state == .done {
                        controlButton("trash", .delete)
                    }
                case .active:
                    controlButton("pause.fill", .pause)
                }
            }
        }
        .padding(8)
        .background(Color.mimo.backgroundAlt)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func controlButton(_ system: String, _ action: Action) -> some View {
        Button(action: { onAction(action) }) {
            Image(systemName: system)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textSecondary)
                .frame(width: 26, height: 22)
                .background(Color.mimo.surface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private func statusIcon(for status: UserGoal.PlanItem.Status) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .inProgress: return "circle.circle"
        case .blocked: return "exclamationmark.circle"
        case .todo: return "circle"
        }
    }

    private func statusColor(for status: UserGoal.PlanItem.Status) -> Color {
        switch status {
        case .done: return Color.mimo.success
        case .inProgress: return Color.mimo.textSecondary
        case .blocked: return Color.mimo.error
        case .todo: return Color.mimo.textMuted
        }
    }
}
