import SwiftUI
import Foundation

/// Right-panel «ЦЕЛЬ» section, redesigned for visual clarity:
///
/// - a section header with a target icon, a count badge and an explicit
///   «add» affordance (the goal is creatable from the interface, not only via
///   `/goal`);
/// - one card per goal with a coloured status rail, a readable status chip
///   (dot + label, never colour alone), a progress bar and an expandable plan;
/// - a primary action button for the goal's main transition (Старт/Продолжить)
///   plus a separated, two-step destructive delete;
/// - a centred empty state with a call to action instead of a dead grey box.
///
/// Reads and writes the disk-backed GoalStore (`~/.mycoder/goals.json`), so it
/// always reflects the same data the `/goal` command and auto-verification use.
struct GoalsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var goals: [UserGoal] = []
    @State private var isCreating = false
    @State private var newGoalTitle = ""

    private var language: AppLanguage { appState.appLanguage }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Scope of the ЦЕЛЬ section: the chat's project, the selected workspace,
    /// or nothing. The goal cards below are filtered by it so a goal never
    /// floats across chats (user directive 2026-11-08).
    private var goalContext: GoalContext {
        GoalContextLogic.context(
            chatID: appState.selectedSession?.id,
            sessionDirectory: appState.selectedSession?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isCreating {
                creationRow
            }

            if goals.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        GoalRow(
                            goal: goal,
                            language: language,
                            onAction: { action in apply(action, to: goal) },
                            onEdit: { newTitle in applyEdit(newTitle, to: goal) }
                        )
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .init("myCoderGoalStoreChanged"))) { _ in
            reload()
        }
        .onChange(of: goalContext) { _ in
            reload()
        }
        // The section must not absorb the panel's leftover height: the goal
        // cards keep their natural size and the panel's Spacer takes the rest.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .interfaceFont(size: 13, weight: .semibold)
                .foregroundColor(Color.mimo.brand)
            Text(L.t(AppLocalizationKey.locGoalTitle))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textSecondary)
                .textCase(.uppercase)
            if !goals.isEmpty {
                Text("\(goals.count)")
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.mimo.backgroundAlt)
                    .clipShape(Capsule())
            }
            Spacer()
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { reload() } }) {
                Image(systemName: "arrow.clockwise")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locGoalRefresh))
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { isCreating.toggle() } }) {
                Image(systemName: isCreating ? "xmark" : "plus")
                    .interfaceFont(size: 11, weight: .bold)
                    .foregroundColor(isCreating ? Color.mimo.textSecondary : Color.mimo.surface)
                    .frame(width: 22, height: 22)
                    .background(isCreating ? Color.mimo.backgroundAlt : Color.mimo.brand)
                    .clipShape(Circle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locGoalNew))
        }
    }

    // MARK: - Creation

    private var creationRow: some View {
        HStack(spacing: 6) {
            TextField(L.t(AppLocalizationKey.locGoalNewPlaceholder), text: $newGoalTitle)
                .textFieldStyle(PlainTextFieldStyle())
                .interfaceFont(size: 12)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.mimo.input)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .onSubmit(createGoal)
            Button(action: createGoal) {
                Text(L.t(AppLocalizationKey.locGoalAdd))
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.surface)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(canCreate ? Color.mimo.brand : Color.mimo.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(!canCreate)
        }
    }

    private var canCreate: Bool {
        !newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createGoal() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = goalContext
        let goal = UserGoal(
            title: trimmed,
            state: .pending,
            projectPath: context.projectPath,
            chatID: context.chatID
        )
        _ = try? GoalStore.upsert(goal, homeDirectory: home)
        // Новая цель стартует сразу (директива 2026-11-13): не нужно
        // отдельно нажимать «Старт» — полный промпт уходит в текущий чат.
        _ = GoalLauncher.launch(
            goalID: goal.id,
            homeDirectory: home,
            language: language,
            fallbackChatID: appState.selectedSession?.id
        )
        newGoalTitle = ""
        withAnimation(.easeOut(duration: 0.15)) {
            isCreating = false
            reload()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .interfaceFont(size: 20, weight: .light)
                .foregroundColor(Color.mimo.brand)
                .padding(10)
                .background(Color.mimo.brand.opacity(0.10))
                .clipShape(Circle())
            Text(L.t(AppLocalizationKey.locGoalEmpty))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { isCreating = true } }) {
                Text(L.t(AppLocalizationKey.locGoalCreate))
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.surface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.mimo.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Color.mimo.backgroundAlt.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data

    private func reload() {
        goals = GoalContextLogic.visibleGoals(
            GoalStore.load(homeDirectory: home),
            context: goalContext
        )
    }

    private func apply(_ action: GoalRow.Action, to goal: UserGoal) {
        switch action {
        case .start:
            // Старт цели = автономный запуск: цель помечается активной и её
            // полный промпт уходит в чат как юзер (с контекстом), дальше —
            // авто-проверка и продолжение до выполнения.
            _ = GoalLauncher.launch(
                goalID: goal.id,
                homeDirectory: home,
                language: language,
                fallbackChatID: appState.selectedSession?.id
            )
        case .pause:
            _ = try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: home)
        case .resume:
            _ = GoalLauncher.launch(
                goalID: goal.id,
                homeDirectory: home,
                language: language,
                fallbackChatID: appState.selectedSession?.id
            )
        case .delete:
            _ = try? GoalStore.remove(id: goal.id, homeDirectory: home)
        }
        withAnimation(.easeOut(duration: 0.15)) { reload() }
    }

    private func applyEdit(_ newTitle: String, to goal: UserGoal) {
        _ = try? GoalStore.updateTitle(id: goal.id, title: newTitle, homeDirectory: home)
        withAnimation(.easeOut(duration: 0.15)) { reload() }
    }
}
