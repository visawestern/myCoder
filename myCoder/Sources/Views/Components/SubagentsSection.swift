import SwiftUI

/// Right-panel sub-agent list: at most five fixed-height rows, a scroll for
/// the rest, sibling listing while a child is open, and a parent breadcrumb.
/// Split from RightPanelView.swift to keep every file under 600 lines.
struct SubagentsSection: View {
    @EnvironmentObject var appState: AppState

    private var language: AppLanguage { appState.appLanguage }
    private var total: Int { appState.subagentSessions.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: RightPanelLayout.subagentsIcon)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.violet)
                Text(AppLocalization.string(.subagentsTitle, language: language))
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text("\(total)")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Spacer(minLength: 0)
            }

            // A child chat keeps the section alive: list its siblings and
            // offer one click back to the parent instead of an empty panel.
            if let parent = appState.subagentParentSession {
                parentButton(parent)
            }

            if total > 0 {
                // Fixed viewport: at most five rows are visible, the rest
                // scroll inside this height (user directive 2026-11-13).
                ScrollView(.vertical,
                           showsIndicators: SubagentListLogic.shouldScroll(total: total)) {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.subagentSessions) { session in
                            SubagentRow(
                                session: session,
                                isSelected: session.id == appState.selectedSession?.id
                            ) {
                                appState.selectSession(session)
                            }
                            .frame(height: SubagentListLogic.rowHeight)
                        }
                    }
                }
                .frame(height: SubagentListLogic.listHeight(total: total))
                .clipped()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Breadcrumb shown while the user reads a child chat.
    ///
    /// - Parameter parent: the chat that spawned the visible sub-agent.
    private func parentButton(_ parent: ChatSession) -> some View {
        Button {
            appState.selectSession(parent)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .interfaceFont(size: 9, weight: .semibold)
                Text(parent.title)
                    .interfaceFont(size: 11)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundColor(Color.mimo.textSecondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.mimo.surfaceHover)
            .cornerRadius(6)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.subagentBackToParent))
        .accessibilityLabel(L.t(AppLocalizationKey.subagentBackToParent))
    }
}

struct SubagentRow: View {
    let session: ChatSession
    /// Highlighted while its transcript is open in the chat panel.
    var isSelected: Bool = false
    let onOpen: () -> Void
    @State private var hovering = false

    private var statusColor: Color {
        switch session.subagentStatus {
        case SubagentRunner.statusRunning: return Color.mimo.warning
        case SubagentRunner.statusFailed: return Color.mimo.error
        default: return Color.mimo.success
        }
    }

    private var statusIcon: String {
        switch session.subagentStatus {
        case SubagentRunner.statusRunning: return RightPanelLayout.subagentRunningIcon
        case SubagentRunner.statusFailed: return RightPanelLayout.subagentFailedIcon
        default: return RightPanelLayout.subagentDoneIcon
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .interfaceFont(size: 10, weight: .semibold)
                    .foregroundColor(statusColor)
                    .frame(width: 12, alignment: .center)
                Text(session.title)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(session.durationLabel)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color.mimo.brand.opacity(0.14)
                    : (hovering ? Color.mimo.brand.opacity(0.08) : Color.clear)
            )
            .cornerRadius(6)
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { hovering = $0 }
        .help(session.title)
    }
}

