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
    @State private var confirmingDelete = false

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
        .confirmationDialog(
            L.t(AppLocalizationKey.locGoalDeleteConfirm),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L.t(AppLocalizationKey.locGoalDelete), role: .destructive) {
                deleteGoal()
            }
            Button(L.t(AppLocalizationKey.locGoalCancel), role: .cancel) {}
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
        guard let visibleGoal = goals.first(where: { $0.state == .active })
            ?? goals.first(where: { $0.state != .done }) else {
            goal = nil
            return
        }
        // Goals created before the todo→plan sync may have an empty plan even
        // though the checklist already exists on disk. Recover it once and
        // persist, so the panel (and the next relaunch) shows the real steps.
        var healed = visibleGoal
        healed.plan = GoalPlanSyncService.healPlanIfNeeded(
            for: visibleGoal,
            homeDirectory: home
        )
        goal = healed
    }

    /// Apply a soft state transition from the composer row. Input: target
    /// state. Output: none; start launches the full goal prompt through the
    /// normal send path, pause only persists the state. Depends on GoalStore,
    /// GoalLauncher and the goal-changed notification.
    private func apply(_ state: UserGoal.State) {
        guard let goal else { return }
        if state == .active {
            // Старт/Продолжить из панели композера — автономный запуск:
            // полный промпт уходит в чат как юзер.
            _ = GoalLauncher.launch(
                goalID: goal.id,
                homeDirectory: home,
                language: language,
                fallbackChatID: context.chatID
            )
        } else {
            _ = try? GoalStore.setState(id: goal.id, state: state, homeDirectory: home)
        }
        NotificationCenter.default.post(name: .init("myCoderGoalStoreChanged"), object: nil)
        reload()
    }

    /// Hard stop: pause the goal AND abort the turn that is currently running
    /// for this chat. Input: none (uses the visible goal). Output: none.
    /// Depends on GoalStore, the global stop-generation notification and the
    /// goal-changed notification. A stopped goal stays resumable.
    private func stopGoal() {
        guard let goal else { return }
        _ = try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: home)
        NotificationCenter.default.post(name: .stopGeneration, object: nil)
        NotificationCenter.default.post(name: .init("myCoderGoalStoreChanged"), object: nil)
        reload()
    }

    /// Delete the visible goal after the confirmation dialog. Input: none.
    /// Output: none. Depends on GoalStore and the goal-changed notification;
    /// the panel reloads and shows the "no goal" state.
    private func deleteGoal() {
        guard let goal else { return }
        _ = try? GoalStore.remove(id: goal.id, homeDirectory: home)
        NotificationCenter.default.post(name: .init("myCoderGoalStoreChanged"), object: nil)
        reload()
    }

    /// Collapsed composer row: title, state, progress and the session controls.
    /// Input: the visible goal. Output: the header view. Depends on
    /// `GoalPresentation` for which controls are legal in the current state.
    private func header(for goal: UserGoal) -> some View {
        HStack(spacing: 6) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())

            controls(for: goal)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    /// Start / pause / stop / delete directly in the collapsed goal row.
    /// Input: the visible goal. Output: icon buttons gated by
    /// `GoalPresentation` (start when not running, pause+stop while running,
    /// delete always). Depends on `apply`, `stopGoal`, `confirmingDelete`.
    private func controls(for goal: UserGoal) -> some View {
        let presentation = GoalPresentation(goal: goal)
        return HStack(spacing: 4) {
            if presentation.canStart {
                controlButton(
                    icon: "play.fill",
                    help: L.t(AppLocalizationKey.locGoalStart),
                    tint: Color.mimo.brand
                ) {
                    apply(.active)
                }
            }
            if presentation.canPause {
                controlButton(
                    icon: "pause.fill",
                    help: L.t(AppLocalizationKey.locGoalPause),
                    tint: Color.mimo.warning
                ) {
                    apply(.paused)
                }
            }
            if presentation.canStop {
                controlButton(
                    icon: "stop.fill",
                    help: L.t(AppLocalizationKey.locGoalStopHint),
                    tint: Color.mimo.error
                ) {
                    stopGoal()
                }
            }
            controlButton(
                icon: "trash",
                help: L.t(AppLocalizationKey.locGoalDeleteHint),
                tint: Color.mimo.textMuted
            ) {
                confirmingDelete = true
            }
        }
    }

    /// One compact icon button of the collapsed goal row. Input: SF Symbol,
    /// tooltip, tint and action. Output: a borderless button view. No external
    /// dependencies beyond the app theme.
    private func controlButton(icon: String,
                               help: String,
                               tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .interfaceFont(size: 9, weight: .semibold)
                .foregroundColor(tint)
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(help)
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
