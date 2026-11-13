import SwiftUI
import Foundation

/// One goal card: status rail, title, status chip, progress and the goal's
/// lifecycle actions.
///
/// The card deliberately has NO plan list (user directive 2026-11-13): the
/// plan is ONE — the chat's step list in the right panel — and is marked
/// there. The card only shows progress derived from that same plan
/// (`goal.plan` is kept in sync with the chat steps by `GoalPlanSyncService`).
struct GoalRow: View {
    enum Action {
        case start, pause, resume, delete
    }

    let goal: UserGoal
    let language: AppLanguage
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
                if presentation.showsProgress {
                    progressBlock
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

    // MARK: - Progress (of the ONE shared plan)

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
}
