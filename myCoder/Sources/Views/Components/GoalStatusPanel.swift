import SwiftUI
import Foundation

/// The composer status-line for a ЦЕЛЬ goal. One line shows the goal, its
/// state and plan progress; expanding it reveals the plan steps, the quick
/// actions (start/pause/resume) and the full prompt. Reads the disk GoalStore
/// so it always matches `/goal`, the sidebar and the API.
///
/// The goal is scoped to the current chat/project (user directive 2026-11-08):
/// `GoalStatusPanel(context:)` never shows another chat's goal.
struct GoalStatusPanel: View {
    var context: GoalContext = GoalContext()
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
                        Divider()
                        actions(for: goal)
                        Divider()
                        GoalPromptView(text: GoalPromptBuilder.fullPrompt(goal: goal, language: language),
                                       language: language)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color.mimo.backgroundAlt)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            } else if context.hasChat || context.hasProject {
                // A chat/project is open but has no goal: say so instead of
                // silently showing a goal from another chat.
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                    Text(L.t(AppLocalizationKey.locGoalNoneInChat))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .init("myCoderGoalStoreChanged"))) { _ in
            reload()
        }
        .onChange(of: context) { _ in
            reload()
        }
    }

    private var language: AppLanguage {
        LocalizationRuntime.currentLanguage
    }

    private func reload() {
        let goals = GoalContextLogic.visibleGoals(
            GoalStore.load(homeDirectory: home),
            context: context
        )
        // Prefer the active goal; fall back to the newest non-done goal so
        // the panel is meaningful even before `/goal start`.
        goal = goals.first(where: { $0.state == .active })
            ?? goals.first(where: { $0.state != .done })
    }

    private func apply(_ state: UserGoal.State) {
        guard let goal else { return }
        _ = try? GoalStore.setState(id: goal.id, state: state, homeDirectory: home)
        NotificationCenter.default.post(name: .init("myCoderGoalStoreChanged"), object: nil)
        reload()
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
                Text(stateLabel(goal.state))
                    .interfaceFont(size: 9, weight: .medium)
                    .foregroundColor(stateColor(goal.state))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(stateColor(goal.state).opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 8)
                Image(systemName: "checklist")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
                Text(progressText(for: goal))
                    .interfaceFont(size: 11, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private func actions(for goal: UserGoal) -> some View {
        HStack(spacing: 8) {
            if goal.state == .active {
                actionButton(L.t(AppLocalizationKey.locGoalPause), icon: "pause.fill") {
                    apply(.paused)
                }
            } else if goal.state == .paused || goal.state == .error || goal.state == .pending {
                actionButton(
                    L.t(goal.state == .pending
                        ? AppLocalizationKey.locGoalStart
                        : AppLocalizationKey.locGoalResume),
                    icon: "play.fill"
                ) {
                    apply(.active)
                }
            }
            Spacer(minLength: 0)
            Text(L.t(AppLocalizationKey.locGoalPlan))
                .interfaceFont(size: 9)
                .foregroundColor(Color.mimo.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .interfaceFont(size: 8, weight: .semibold)
                Text(title)
                    .interfaceFont(size: 10, weight: .medium)
            }
            .foregroundColor(Color.mimo.brand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.mimo.brand.opacity(0.10))
            .clipShape(Capsule())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private func planList(for goal: UserGoal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if goal.plan.isEmpty {
                Text(L.t(AppLocalizationKey.locGoalPlanHint))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            } else {
                ForEach(Array(goal.plan.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: item.status))
                            .interfaceFont(size: 10)
                            .foregroundColor(color(for: item.status))
                        Text("\(index + 1). \(item.title)")
                            .interfaceFont(size: 11)
                            .foregroundColor(item.status == .done ? Color.mimo.textMuted : Color.mimo.textSecondary)
                            .lineLimit(2)
                            .strikethrough(item.status == .done)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func progressText(for goal: UserGoal) -> String {
        guard !goal.plan.isEmpty else { return "0/0" }
        let done = goal.plan.filter { $0.status == .done }.count
        return "\(done)/\(goal.plan.count)"
    }

    private func stateLabel(_ state: UserGoal.State) -> String {
        switch state {
        case .pending: return L.t(AppLocalizationKey.locGoalCreated)
        case .active: return L.t(AppLocalizationKey.locGoalRunning)
        case .paused: return L.t(AppLocalizationKey.locGoalPaused)
        case .error: return L.t(AppLocalizationKey.locGoalError)
        case .done: return L.t(AppLocalizationKey.locGoalDone)
        }
    }

    private func stateColor(_ state: UserGoal.State) -> Color {
        switch state {
        case .pending: return Color.mimo.textSecondary
        case .active: return Color.mimo.success
        case .paused: return Color.mimo.warning
        case .error: return Color.mimo.error
        case .done: return Color.mimo.success
        }
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
