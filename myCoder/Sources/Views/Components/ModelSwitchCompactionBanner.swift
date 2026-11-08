import SwiftUI

/// Banner of the automatic compaction that follows a model switch into a
/// smaller context window (user directive 2026-11-08).
///
/// The banner is the visible control of that compaction: it explains what
/// happened and offers every way out the user asked for — stop the running
/// compaction, roll it back, run it again, or switch to a model with a larger
/// context window instead of compacting at all.
struct ModelSwitchCompactionBanner: View {
    let notice: ModelSwitchCompactionNotice
    let onStop: () -> Void
    let onRollback: () -> Void
    let onRetry: () -> Void
    let onChooseModel: (ModelSwitchCompactionLogic.Candidate) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(statusText)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = notice.error, !error.isEmpty {
                Text(error)
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .interfaceFont(size: 12, weight: .medium)
                .foregroundColor(tint)
            Text(L.t(AppLocalizationKey.locModelSwitchCompactionTitle))
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .interfaceFont(size: 9, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locModelSwitchCompactionDismiss))
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if notice.canStop {
                actionButton(
                    L.t(AppLocalizationKey.locModelSwitchCompactionStop),
                    icon: "stop.circle"
                ) {
                    onStop()
                }
            }
            if notice.canRollback {
                actionButton(
                    L.t(AppLocalizationKey.locModelSwitchCompactionRollback),
                    icon: "arrow.uturn.backward.circle"
                ) {
                    onRollback()
                }
            }
            if notice.canRetry {
                actionButton(
                    L.t(AppLocalizationKey.locModelSwitchCompactionRetry),
                    icon: "arrow.clockwise.circle"
                ) {
                    onRetry()
                }
            }
            if !notice.alternatives.isEmpty {
                Menu {
                    ForEach(notice.alternatives, id: \.key) { candidate in
                        Button(modelLabel(for: candidate)) {
                            onChooseModel(candidate)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .interfaceFont(size: 10)
                        Text(L.t(AppLocalizationKey.locModelSwitchCompactionChooseModel))
                            .interfaceFont(size: 11)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Text(L.t(AppLocalizationKey.locModelSwitchCompactionNoAlternative))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
    }

    /// "Provider — model", so the user sees where the alternative lives: the
    /// bigger window is often in another provider.
    private func modelLabel(for candidate: ModelSwitchCompactionLogic.Candidate) -> String {
        guard !candidate.providerName.isEmpty else { return candidate.id }
        return L.t(
            AppLocalizationKey.locModelSwitchCompactionModelFormat,
            candidate.providerName,
            candidate.id
        )
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .interfaceFont(size: 10)
                Text(title)
                    .interfaceFont(size: 11)
            }
        }
        .buttonStyle(HandCursorButtonStyle())
        .foregroundColor(Color.mimo.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.mimo.input)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.mimo.inputBorder, lineWidth: 1)
        )
    }

    /// The numbers are the reason for everything: how much context the chat
    /// occupies and how much the new model can hold.
    private var detailsText: String {
        L.t(
            AppLocalizationKey.locModelSwitchCompactionDetails,
            ContextUsageLogic.formatTokens(notice.usedTokens),
            ContextUsageLogic.formatTokens(notice.limitTokens)
        )
    }

    private var statusText: String {
        let phaseText: String
        switch notice.phase {
        case .pending:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionPending)
        case .running:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionRunning)
        case .compacted:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionCompacted)
        case .cancelled:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionCancelled)
        case .failed:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionFailed)
        case .rolledBack:
            phaseText = L.t(AppLocalizationKey.locModelSwitchCompactionRolledBack)
        }
        return "\(phaseText) \(detailsText) · \(notice.newModel)"
    }

    private var tint: Color {
        switch notice.phase {
        case .pending, .running: return Color.mimo.brand
        case .compacted: return Color.mimo.success
        case .cancelled, .rolledBack: return Color.mimo.warning
        case .failed: return Color.mimo.error
        }
    }

    private var iconName: String {
        switch notice.phase {
        case .pending, .running: return "arrow.down.right.and.arrow.up.left"
        case .compacted: return "checkmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .rolledBack: return "arrow.uturn.backward.circle.fill"
        }
    }
}
