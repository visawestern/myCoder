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
    @State private var expandedGoalID: UUID?
    @State private var isCreating = false
    @State private var newGoalTitle = ""

    private var language: AppLanguage { appState.appLanguage }
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

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
                            expanded: expandedGoalID == goal.id,
                            language: language,
                            onToggle: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    expandedGoalID = expandedGoalID == goal.id ? nil : goal.id
                                }
                            },
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
        let goal = UserGoal(title: trimmed, state: .pending)
        _ = try? GoalStore.upsert(goal, homeDirectory: home)
        newGoalTitle = ""
        withAnimation(.easeOut(duration: 0.15)) {
            isCreating = false
            expandedGoalID = goal.id
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
        withAnimation(.easeOut(duration: 0.15)) { reload() }
    }

    private func applyEdit(_ newTitle: String, to goal: UserGoal) {
        _ = try? GoalStore.updateTitle(id: goal.id, title: newTitle, homeDirectory: home)
        withAnimation(.easeOut(duration: 0.15)) { reload() }
    }
}

/// One goal card: status rail, title, status chip, progress, plan spoiler and
/// the goal's lifecycle actions.
struct GoalRow: View {
    enum Action {
        case start, pause, resume, delete
    }

    let goal: UserGoal
    let expanded: Bool
    let language: AppLanguage
    let onToggle: () -> Void
    let onAction: (Action) -> Void
    let onEdit: (String) -> Void

    @State private var confirmingDelete = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showsFullPrompt = false

    /// All display rules live in the pure presentation model.
    private var presentation: GoalPresentation { GoalPresentation(goal: goal) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Status rail — a non-textual anchor for the goal state.
            RoundedRectangle(cornerRadius: 2)
                .fill(stateColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                if presentation.showsPlanHint {
                    planHint
                } else {
                    progressBlock
                    planDisclosure
                }
                if expanded && presentation.showsPlanDisclosure {
                    planList
                }
                actionBar
                fullPromptDisclosure
                if showsFullPrompt {
                    GoalPromptView(text: GoalPromptBuilder.fullPrompt(goal: goal, language: language),
                                   language: language)
                        .padding(.top, 2)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .background(Color.mimo.input)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Title + status

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isEditing {
                HStack(spacing: 6) {
                    TextField(L.t(AppLocalizationKey.locGoalTitlePlaceholder), text: $editText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .interfaceFont(size: 12)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.mimo.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit(saveEdit)
                    Button(action: saveEdit) {
                        Text(L.t(AppLocalizationKey.locGoalSave))
                            .interfaceFont(size: 10.5, weight: .semibold)
                            .foregroundColor(Color.mimo.surface)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(canSave ? Color.mimo.brand : Color.mimo.textMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .disabled(!canSave)
                    Button(action: { isEditing = false }) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 9, weight: .bold)
                            .foregroundColor(Color.mimo.textMuted)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locGoalCancel))
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Text(goal.title)
                        .interfaceFont(size: 12.5, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Button(action: {
                        editText = goal.title
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locGoalEditTitle))
                }
            }
            HStack(spacing: 5) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                Text(stateLabel)
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(stateColor)
            }
        }
    }

    private var canSave: Bool {
        !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onEdit(trimmed)
        isEditing = false
    }

    private var fullPromptDisclosure: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { showsFullPrompt.toggle() } }) {
            HStack(spacing: 5) {
                Image(systemName: showsFullPrompt ? "chevron.down" : "chevron.right")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Text(L.t(AppLocalizationKey.locGoalFullPrompt))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private var stateLabel: String {
        L.t(presentation.stateLabel)
    }

    private var stateColor: Color {
        switch presentation.stateColor {
        case .brand: return Color.mimo.brand
        case .success: return Color.mimo.success
        case .warning: return Color.mimo.warning
        case .error: return Color.mimo.error
        case .muted: return Color.mimo.textMuted
        }
    }

    // MARK: - Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mimo.backgroundAlt)
                    Capsule()
                        .fill(stateColor)
                        .frame(width: max(3, geo.size.width * presentation.progress))
                }
            }
            .frame(height: 4)
            HStack(spacing: 4) {
                Text(L.t(AppLocalizationKey.locGoalStepsDone,
                         presentation.doneCount,
                         presentation.totalCount))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                if presentation.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.success)
                }
            }
        }
    }

    private var planHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "wand.and.stars")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Text(L.t(AppLocalizationKey.locGoalPlanHint))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planDisclosure: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
                Text(L.t(AppLocalizationKey.locGoalPlan))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                Spacer()
                Text("\(presentation.totalCount)")
                    .interfaceFont(size: 9, weight: .medium)
                    .foregroundColor(Color.mimo.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.mimo.backgroundAlt)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(goal.plan.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: statusIcon(for: item.status))
                        .interfaceFont(size: 11)
                        .foregroundColor(statusColor(for: item.status))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .interfaceFont(size: 11)
                            .foregroundColor(item.status == .done
                                             ? Color.mimo.textMuted
                                             : Color.mimo.textSecondary)
                            .strikethrough(item.status == .done, color: Color.mimo.textMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .interfaceFont(size: 9.5)
                                .foregroundColor(Color.mimo.textMuted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                if index < goal.plan.count - 1 {
                    Rectangle()
                        .fill(Color.mimo.border)
                        .frame(height: 1)
                        .padding(.leading, 22)
                }
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            primaryAction
            Spacer(minLength: 0)
            deleteControl
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch presentation.primaryAction {
        case .start:
            actionButton(title: L.t(AppLocalizationKey.locGoalStart), system: "play.fill", action: .start, filled: true)
        case .pause:
            actionButton(title: L.t(AppLocalizationKey.locGoalPause), system: "pause.fill", action: .pause, filled: false)
        case .resume:
            actionButton(title: L.t(AppLocalizationKey.locGoalResume), system: "arrow.clockwise", action: .resume, filled: true)
        case .none:
            EmptyView()
        }
    }

    private func actionButton(title: String, system: String, action: Action, filled: Bool) -> some View {
        Button(action: { onAction(action) }) {
            HStack(spacing: 5) {
                Image(systemName: system)
                    .interfaceFont(size: 9.5, weight: .semibold)
                Text(title)
                    .interfaceFont(size: 10.5, weight: .semibold)
            }
            .foregroundColor(filled ? Color.mimo.surface : Color.mimo.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? Color.mimo.brand : Color.mimo.backgroundAlt)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    @ViewBuilder
    private var deleteControl: some View {
        if confirmingDelete {
            HStack(spacing: 6) {
                Text(L.t(AppLocalizationKey.locGoalDeleteQuestion))
                    .interfaceFont(size: 10, weight: .medium)
                    .foregroundColor(Color.mimo.textSecondary)
                Button(action: {
                    onAction(.delete)
                    confirmingDelete = false
                }) {
                    Text(L.t(AppLocalizationKey.locGoalDelete))
                        .interfaceFont(size: 10, weight: .semibold)
                        .foregroundColor(Color.mimo.surface)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.mimo.error)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                Button(action: { confirmingDelete = false }) {
                    Image(systemName: "xmark")
                        .interfaceFont(size: 9, weight: .bold)
                        .foregroundColor(Color.mimo.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locGoalCancel))
            }
        } else {
            Button(action: { confirmingDelete = true }) {
                Image(systemName: "trash")
                    .interfaceFont(size: 10.5)
                    .foregroundColor(Color.mimo.textMuted)
                    .frame(width: 24, height: 22)
                    .background(Color.mimo.backgroundAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locGoalDeleteHint))
        }
    }

    private func statusIcon(for status: UserGoal.PlanItem.Status) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .inProgress: return "circle.circle"
        case .blocked: return "exclamationmark.triangle.fill"
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
