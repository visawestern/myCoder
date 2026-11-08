import SwiftUI
import Foundation

/// Right-panel «ЦЕЛЬ» section, redesigned around Google/Material UI
/// principles: a clear empty state with a call-to-action, an inline creation
/// path (so goals are creatable from the interface, not only via `/goal`), a
/// progress bar per goal, color-coded status chips, labelled action buttons,
/// and a two-step confirmation for the destructive delete.
struct GoalsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var goals: [UserGoal] = []
    @State private var expandedGoalID: UUID?
    @State private var isCreating = false
    @State private var newGoalTitle = ""

    private var language: AppLanguage { appState.appLanguage }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var title: String {
        language == .russian ? "ЦЕЛЬ" : "GOAL"
    }

    private var emptyMessage: String {
        language == .russian
            ? "Здесь появятся ваши цели. Создайте первую — модель разобьёт её на шаги."
            : "Your goals appear here. Create the first one — the model will split it into steps."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isCreating {
                creationRow
            }

            if goals.isEmpty {
                emptyState
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

    private var header: some View {
        HStack {
            Text(title)
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            Spacer()
            Button(action: { withAnimation { reload() } }) {
                Image(systemName: "arrow.clockwise")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(language == .russian ? "Обновить" : "Refresh")
            Button(action: { withAnimation { isCreating.toggle() } }) {
                Image(systemName: isCreating ? "xmark" : "plus")
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.brand)
                    .frame(width: 22, height: 22)
                    .background(Color.mimo.brand.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(language == .russian ? "Новая цель" : "New goal")
        }
    }

    private var creationRow: some View {
        HStack(spacing: 6) {
            TextField(language == .russian ? "Новая цель…" : "New goal…",
                      text: $newGoalTitle)
                .textFieldStyle(PlainTextFieldStyle())
                .interfaceFont(size: 12)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.mimo.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit(createGoal)
            Button(action: createGoal) {
                Text(language == .russian ? "Добавить" : "Add")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.surface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.mimo.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "flag")
                .interfaceFont(size: 18)
                .foregroundColor(Color.mimo.textMuted)
            Text(emptyMessage)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { withAnimation { isCreating = true } }) {
                Text(language == .russian ? "Создать цель" : "Create a goal")
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(Color.mimo.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.mimo.brand.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.backgroundAlt)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func createGoal() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let goal = UserGoal(title: trimmed, state: .pending)
        _ = try? GoalStore.upsert(goal, homeDirectory: home)
        newGoalTitle = ""
        withAnimation {
            isCreating = false
            expandedGoalID = goal.id
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

/// One goal card: title + status chip, a progress bar, an expandable plan
/// spoiler, and labelled lifecycle actions with confirmation for delete.
struct GoalRow: View {
    enum Action {
        case start, pause, resume, delete
    }

    let goal: UserGoal
    let expanded: Bool
    let language: AppLanguage
    let onToggle: () -> Void
    let onAction: (Action) -> Void

    @State private var confirmingDelete = false

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
        case .active: return Color.mimo.brand
        case .done: return Color.mimo.success
        case .paused, .error: return Color.mimo.warning
        case .pending: return Color.mimo.textMuted
        }
    }

    private var doneCount: Int {
        goal.plan.filter { $0.status == .done }.count
    }

    private var progress: Double {
        guard !goal.plan.isEmpty else { return 0 }
        return Double(doneCount) / Double(goal.plan.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(goal.title)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(stateLabel)
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            if !goal.plan.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(doneCount)/\(goal.plan.count)")
                        .interfaceFont(size: 10, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                }
                Button(action: onToggle) {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                        Text(language == .russian ? "Шаги" : "Steps")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textSecondary)
                        Spacer()
                    }
                }
                .buttonStyle(HandCursorButtonStyle())

                if expanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(goal.plan.enumerated()), id: \.offset) { _, item in
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

            actionBar
        }
        .padding(10)
        .background(Color.mimo.backgroundAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 6) {
            Group {
                switch goal.state {
                case .pending:
                    labelledButton("play.fill", startLabel, .start)
                case .active:
                    labelledButton("pause.fill", pauseLabel, .pause)
                case .paused, .error:
                    labelledButton("arrow.clockwise", resumeLabel, .resume)
                case .done:
                    EmptyView()
                }
            }
            Spacer()
            deleteControl
        }
    }

    private var startLabel: String {
        language == .russian ? "Старт" : "Start"
    }
    private var pauseLabel: String {
        language == .russian ? "Пауза" : "Pause"
    }
    private var resumeLabel: String {
        language == .russian ? "Продолжить" : "Resume"
    }
    private var deleteLabel: String {
        language == .russian ? "Удалить" : "Delete"
    }
    private var confirmDeleteLabel: String {
        language == .russian ? "Точно?" : "Sure?"
    }

    private func labelledButton(_ system: String, _ label: String, _ action: Action) -> some View {
        Button(action: { onAction(action) }) {
            HStack(spacing: 5) {
                Image(systemName: system)
                    .interfaceFont(size: 10)
                Text(label)
                    .interfaceFont(size: 10, weight: .medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    @ViewBuilder
    private var deleteControl: some View {
        if confirmingDelete {
            Button(action: {
                onAction(.delete)
                confirmingDelete = false
            }) {
                Text(confirmDeleteLabel)
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(Color.mimo.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mimo.error.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(HandCursorButtonStyle())
        } else if goal.state != .done {
            Button(action: { confirmingDelete = true }) {
                Image(systemName: "trash")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(deleteLabel)
        }
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
        case .inProgress: return Color.mimo.brand
        case .blocked: return Color.mimo.error
        case .todo: return Color.mimo.textMuted
        }
    }
}
