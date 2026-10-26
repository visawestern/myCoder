import SwiftUI

enum TaskHeaderVisibility {
    static func shouldShow(selectedSession: ChatSession?) -> Bool {
        selectedSession != nil
    }
}

struct TopBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var chatCopied = false

    var body: some View {
        HStack(spacing: 12) {
            // Sidebar toggle — always visible
            Button(action: { withAnimation { appState.sidebarVisible.toggle() } }) {
                Image(systemName: "sidebar.left")
                    .interfaceFont(size: 14)
                    .foregroundColor(appState.sidebarVisible ? Color.mimo.brand : Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help("Workspaces")

            // Session title — only when session is selected
            if let session = appState.selectedSession {
                Text(session.title)
                    .interfaceFont(size: 14, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                    .lineLimit(1)
            }

            // Workspace folder badge — only when workspace is selected
            if let workspace = appState.selectedWorkspace {
                HStack(spacing: 4) {
                    Image(systemName: ProjectlessWorkspaceLogic.isProjectless(workspace)
                          ? "bubble.left.and.bubble.right"
                          : "folder.fill")
                        .interfaceFont(size: 10)
                    Text(ProjectlessWorkspaceLogic.isProjectless(workspace)
                         ? L.t("No project")
                         : workspace.name)
                        .interfaceFont(size: 11, weight: .medium)
                }
                .foregroundColor(Color.mimo.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.mimo.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Branch badge — when project is selected
            if ProjectHeaderContextLogic.shouldShowBranch(
                selectedWorkspace: appState.selectedWorkspace != nil,
                selectedLegacyProject: appState.selectedProject != nil
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .interfaceFont(size: 10)
                    Text(appState.gitBranch)
                        .interfaceFont(size: 11, design: .monospaced)
                }
                .foregroundColor(Color.mimo.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.mimo.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // Fallback "myCoder" text when no project is open
                Text(L.t(AppLocalizationKey.locMycoder))
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                    .tracking(0.5)
            }

            // Task board for the selected project (spec-wizard projects keep
            // their tasks after setup, so this must stay reachable).
            if let workspace = appState.selectedWorkspace,
               workspace.id != ChatSession.standaloneProjectKey {
                ProjectTasksButton(workspace: workspace)
            }

            // Session goal badge with live checklist progress (roadmap G).
            if HeaderGoalProgressLogic.shouldShow(
                selectedSession: appState.selectedSession,
                goal: appState.currentSessionGoal,
                steps: appState.currentSteps
            ),
               let badge = HeaderGoalProgressLogic.badgeText(
                goal: appState.currentSessionGoal,
                steps: appState.currentSteps
               ) {
                HeaderGoalChecklistBadge(
                    badge: badge,
                    goal: appState.currentSessionGoal,
                    steps: appState.currentSteps
                )
            }

            if let notice = appState.shellActionNotice {
                HStack(spacing: 4) {
                    Image(systemName: appState.shellActionNoticeTone == .error
                          ? "exclamationmark.triangle"
                          : appState.shellActionNoticeTone == .warning
                            ? "minus.circle"
                            : "checkmark.circle")
                        .interfaceFont(size: 10)
                    Text(notice)
                        .interfaceFont(size: 11)
                        .lineLimit(1)
                }
                .foregroundColor(
                    appState.shellActionNoticeTone == .error
                        ? Color.mimo.error
                        : appState.shellActionNoticeTone == .warning
                            ? Color.mimo.warning
                            : Color.mimo.success
                )
                .transition(.opacity)
            }

            Spacer()

            // Copy entire chat — only when session is selected
            if appState.selectedSession != nil {
                Button(action: copyEntireChat) {
                    Image(systemName: chatCopied ? "checkmark" : "doc.on.doc")
                        .interfaceFont(size: 14)
                        .foregroundColor(chatCopied ? Color.mimo.success : Color.mimo.textSecondary)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(chatCopied ? L.t(AppLocalizationKey.locCopied) : L.t(AppLocalizationKey.locCopyChat))
            }

            // Action buttons — always visible
            TopBarButton(
                icon: "flag",
                label: L.t(AppLocalizationKey.locGoal),
                isActive: appState.showGoal,
                action: { appState.showGoal.toggle() }
            )

            TopBarButton(
                icon: "terminal",
                label: L.t(AppLocalizationKey.locTerminal),
                isActive: appState.showTerminal,
                action: { appState.showTerminal.toggle() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.mimo.surface)
        .onReceive(NotificationCenter.default.publisher(for: .copyEntireChatCompleted)) { _ in
            withAnimation { chatCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { chatCopied = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyEntireChatUnavailable)) { _ in
            withAnimation { chatCopied = false }
        }
    }

    private func copyEntireChat() {
        NotificationCenter.default.post(name: .copyEntireChat, object: nil)
    }
}

struct TopBarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .interfaceFont(size: 14)

                Text(label)
                    .interfaceFont(size: 12, weight: isActive ? .semibold : .regular)
            }
            .foregroundColor(isActive ? Color.mimo.brand : Color.mimo.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.mimo.brand.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.mimo.brand.opacity(0.5) : Color.mimo.border, lineWidth: 1)
            )
        }
        .buttonStyle(HandCursorButtonStyle())
    }
}

/// Goal badge with live `n/m` progress and an expandable step checklist
/// (roadmap item G). Without steps it renders as the plain goal badge.
struct HeaderGoalChecklistBadge: View {
    let badge: String
    let goal: String?
    let steps: [TaskStep]
    @State private var showSteps = false

    var body: some View {
        Button(action: { if !steps.isEmpty { showSteps.toggle() } }) {
            HStack(spacing: 6) {
                Text(badge)
                    .interfaceFont(size: 11, weight: .medium)
                if let fraction = HeaderGoalProgressLogic.progressFraction(steps: steps) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 44)
                }
            }
            .foregroundColor(Color.mimo.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.mimo.brand.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(goal ?? badge)
        .popover(isPresented: $showSteps, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(steps) { step in
                    HStack(spacing: 6) {
                        Image(systemName: HeaderGoalProgressLogic.stepIconName(for: step.status))
                            .interfaceFont(size: 10)
                            .foregroundColor(step.status == .completed ? Color.mimo.success : Color.mimo.textSecondary)
                        Text(step.title)
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textPrimary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 220, maxWidth: 340)
        }
    }
}

struct ChatPanelCompactHeader: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { withAnimation { appState.sidebarVisible.toggle() } }) {
                Image(systemName: "sidebar.left")
                    .interfaceFont(size: 14)
                    .foregroundColor(appState.sidebarVisible ? Color.mimo.brand : Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help("Workspaces")

            Spacer()

            Button(action: { appState.showGoal.toggle() }) {
                Image(systemName: "sidebar.right")
                    .interfaceFont(size: 14)
                    .foregroundColor(appState.showGoal ? Color.mimo.brand : Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help("Git tools & progress")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mimo.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}


/// Opens the spec task board only for projects that actually have a wizard
/// draft; empty projects must not be turned into wizard projects by a click.
private struct ProjectTasksButton: View {
    @EnvironmentObject var appState: AppState
    let workspace: Workspace
    @State private var hasDraft = false

    var body: some View {
        Group {
            if hasDraft {
                Button {
                    appState.openSpecWizard(for: workspace.path)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .interfaceFont(size: 10)
                        Text(L.t("Project tasks"))
                            .interfaceFont(size: 11, weight: .medium)
                    }
                    .foregroundColor(Color.mimo.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mimo.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t("Project tasks"))
            }
        }
        .task(id: workspace.path) {
            hasDraft = DatabaseBridge.shared.loadSpecWizardDraft(
                projectPath: ChatSession.normalizedPath(workspace.path)
            ) != nil
        }
    }
}
