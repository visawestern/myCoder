import SwiftUI
import Foundation

/// The composer status-line spoiler for an active ЦЕЛЬ goal. One line shows
/// the goal and plan progress; expanding it reveals the plan steps (a
/// spoiler, matching the context-assembly panel). Reads the disk GoalStore so
/// it always matches `/goal` and the sidebar.
struct GoalStatusPanel: View {
    @State private var goal: UserGoal?
    @State private var isExpanded = false

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var body: some View {
        Group {
            if let goal {
                VStack(alignment: .leading, spacing: 0) {
                    header(for: goal)
                    if isExpanded {
                        Divider()
                        planList(for: goal)
                    }
                }
                .background(Color.mimo.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let goals = GoalStore.load(homeDirectory: home)
        // Prefer the active goal; fall back to the newest non-done goal so
        // the panel is meaningful even before `/goal start`.
        goal = goals.first(where: { $0.state == .active })
            ?? goals.first(where: { $0.state != .done })
    }

    private func header(for goal: UserGoal) -> some View {
        Button(action: { withAnimation { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Text("🎯")
                    .interfaceFont(size: 11)
                Text(goal.title)
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(progressText(for: goal))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private func planList(for goal: UserGoal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(goal.plan.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: item.status))
                        .interfaceFont(size: 10)
                        .foregroundColor(color(for: item.status))
                    Text(item.title)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func progressText(for goal: UserGoal) -> String {
        guard !goal.plan.isEmpty else { return "план строится…" }
        let done = goal.plan.filter { $0.status == .done }.count
        return "\(done)/\(goal.plan.count)"
    }

    private func icon(for status: UserGoal.PlanItem.Status) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .inProgress: return "circle.circle"
        case .blocked: return "exclamationmark.circle"
        case .todo: return "circle"
        }
    }

    private func color(for status: UserGoal.PlanItem.Status) -> Color {
        switch status {
        case .done: return Color.mimo.success
        case .inProgress: return Color.mimo.textSecondary
        case .blocked: return Color.mimo.error
        case .todo: return Color.mimo.textMuted
        }
    }
}
