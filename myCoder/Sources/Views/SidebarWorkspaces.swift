import SwiftUI
import AppKit
struct WorkspacesSectionHeader: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullWorkspaceToolbar
            compactWorkspaceToolbar
        }
        .padding(.bottom, 6)
    }

    private var fullWorkspaceToolbar: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation { appState.workspacesSectionExpanded.toggle() } }) {
                Image(systemName: appState.workspacesSectionExpanded ? "chevron.down" : "chevron.right")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(appState.workspacesSectionExpanded ? L.t(AppLocalizationKey.locCollapseWorkspaces) : L.t(AppLocalizationKey.locExpandWorkspaces))

            Button(action: { appState.showWorkspacesOverview = true }) {
                Image(systemName: SidebarLayout.workspacesExpandIcon)
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locAllWorkspaces))

            Spacer(minLength: 4)
            archiveButton
            sortMenu
            filterMenu
            searchButton
            viewModeButton
        }
    }

    private var compactWorkspaceToolbar: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation { appState.workspacesSectionExpanded.toggle() } }) {
                Image(systemName: appState.workspacesSectionExpanded ? "chevron.down" : "chevron.right")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(appState.workspacesSectionExpanded ? L.t(AppLocalizationKey.locCollapseWorkspaces) : L.t(AppLocalizationKey.locExpandWorkspaces))

            Spacer(minLength: 4)
            Menu {
                workspaceOverflowMenu
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.t(AppLocalizationKey.locWorkspaceActions))
        }
    }

    @ViewBuilder
    private var workspaceOverflowMenu: some View {
        Button {
            withAnimation { appState.workspacesSectionExpanded.toggle() }
        } label: {
            Label(appState.workspacesSectionExpanded ? L.t(AppLocalizationKey.locCollapseWorkspaces) : L.t(AppLocalizationKey.locExpandWorkspaces),
                  systemImage: appState.workspacesSectionExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
        }
        Button { appState.showWorkspacesOverview = true } label: {
            Label(L.t(AppLocalizationKey.locAllWorkspaces), systemImage: SidebarLayout.workspacesExpandIcon)
        }
        Button { appState.showArchivePopover.toggle() } label: {
            Label(L.t(AppLocalizationKey.locArchivedProjects), systemImage: "archivebox")
        }
        Menu(L.t(AppLocalizationKey.locSortWorkspaces)) {
            ForEach(WorkspaceSortOrder.allCases) { order in
                Button {
                    appState.workspaceSortOrder = order
                } label: {
                    Label(order.rawValue, systemImage: appState.workspaceSortOrder == order ? "checkmark" : "")
                }
            }
        }
        Menu(L.t(AppLocalizationKey.locFilterWorkspaces)) {
            ForEach(WorkspaceFilterPreset.allCases, id: \.self) { preset in
                Button {
                    appState.workspaceFilterPreset = preset
                } label: {
                    Label(preset.rawValue, systemImage: appState.workspaceFilterPreset == preset ? "checkmark" : "")
                }
            }
        }
        Button {
            withAnimation {
                appState.showWorkspaceSearchField.toggle()
                if !appState.showWorkspaceSearchField { appState.workspaceFilterQuery = "" }
            }
        } label: {
            Label(appState.showWorkspaceSearchField ? L.t(AppLocalizationKey.locHideWorkspaceSearch) : L.t(AppLocalizationKey.locShowWorkspaceSearch),
                  systemImage: SidebarLayout.workspacesSearchIcon)
        }
        Button {
            withAnimation {
                appState.workspaceViewMode = appState.workspaceViewMode == .list ? .grid : .list
            }
        } label: {
            Label(appState.workspaceViewMode == .list ? L.t(AppLocalizationKey.locShowGrid) : L.t(AppLocalizationKey.locShowList),
                  systemImage: appState.workspaceViewMode == .list ? SidebarLayout.workspacesViewGridIcon : SidebarLayout.workspacesViewListIcon)
        }
    }

    private var archiveButton: some View {
        Button(action: { appState.showArchivePopover.toggle() }) {
            Image(systemName: "archivebox")
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locArchivedProjects))
        .popover(isPresented: $appState.showArchivePopover) {
            ArchivedProjectsPopover().environmentObject(appState)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(WorkspaceSortOrder.allCases) { order in
                Button(action: { appState.workspaceSortOrder = order }) {
                    HStack {
                        Text(order.rawValue)
                        if appState.workspaceSortOrder == order { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: SidebarLayout.workspacesFilterIcon)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L.t(AppLocalizationKey.locSortWorkspaces))
    }

    private var filterMenu: some View {
        Menu {
            ForEach(WorkspaceFilterPreset.allCases, id: \.self) { preset in
                Button(action: { appState.workspaceFilterPreset = preset }) {
                    HStack {
                        Text(preset.rawValue)
                        if appState.workspaceFilterPreset == preset { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: appState.workspaceFilterPreset == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .interfaceFont(size: 11)
                .foregroundColor(appState.workspaceFilterPreset != .all ? Color.mimo.brand : Color.mimo.textMuted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L.t("Filter: %@", appState.workspaceFilterPreset.rawValue))
    }

    private var searchButton: some View {
        Button(action: {
            withAnimation {
                appState.showWorkspaceSearchField.toggle()
                if !appState.showWorkspaceSearchField { appState.workspaceFilterQuery = "" }
            }
        }) {
            Image(systemName: SidebarLayout.workspacesSearchIcon)
                .interfaceFont(size: 11)
                .foregroundColor(appState.showWorkspaceSearchField ? Color.mimo.brand : Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locFilterWorkspaces))
    }

    private var viewModeButton: some View {
        Button(action: {
            withAnimation {
                appState.workspaceViewMode = appState.workspaceViewMode == .list ? .grid : .list
            }
        }) {
            Image(systemName: appState.workspaceViewMode == .list ? SidebarLayout.workspacesViewGridIcon : SidebarLayout.workspacesViewListIcon)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t("Toggle list/grid view"))
    }
}

struct WorkspaceGridView: View {
    let workspaces: [Workspace]
    @EnvironmentObject var appState: AppState
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(workspaces) { workspace in
                Button(action: { appState.selectWorkspace(workspace) }) {
                    VStack(spacing: 6) {
                        ProjectAvatarView(
                            workspace: workspace,
                            size: 26,
                            fallbackColor: appState.selectedWorkspace?.id == workspace.id ? Color.mimo.brand : Color.mimo.textMuted,
                            fallbackSymbol: "folder.fill"
                        )
                        Text(workspace.name)
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(8)
                    .background(appState.selectedWorkspace?.id == workspace.id ? Color.mimo.surfaceHover : Color.mimo.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(HandCursorButtonStyle())
            }
        }
    }
}

struct SidebarActionRow: View {
    let icon: String
    let label: String
    var shortcut: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .interfaceFont(size: 13)
                    .frame(width: 18)
                    .foregroundColor(Color.mimo.textSecondary)
                Text(label)
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
    }
}

struct WorkspaceSidebarSection: View {
    let workspace: Workspace
    /// The project's chats, taken from the sidebar tree so every project can
    /// show its own children (F71).
    var sessions: [ChatSession] = []
    /// Whether the project is pinned to the top of the sidebar.
    var isPinned: Bool = false
    /// Whether this group should start expanded — only the active project is
    /// expanded by default; other groups start collapsed (plan Раздел 13 п.6).
    let startsExpanded: Bool
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool
    @State private var hoveredSessionID: String?
    @State private var isHovered = false
    @State private var projectNeedsAttentionNow = false

    /// «Звоночек» проекта: хотя бы один его чат ждёт решения пользователя.
    /// Когда проект скрыт (свёрнут), моргает сам проект.
    private func refreshAttention() {
        projectNeedsAttentionNow = workspaceSessions.contains { session in
            SidebarAttentionLogic.chatNeedsAttention(
                sessionID: session.id,
                pendingApprovalCount: ToolApprovalCenter.shared.pendingCount(in: session.id),
                pendingQuestionSessionID: appState.pendingQuestionRequest?.sessionID
            )
        }
    }

    init(
        workspace: Workspace,
        sessions: [ChatSession] = [],
        isPinned: Bool = false,
        startsExpanded: Bool = false
    ) {
        self.workspace = workspace
        self.sessions = sessions
        self.isPinned = isPinned
        self.startsExpanded = startsExpanded
        _isExpanded = State(initialValue: startsExpanded)
    }
    
    private static let groupColors: [Color] = [
        Color(red: 0.49, green: 0.23, blue: 0.93), // brand purple
        Color(red: 0.20, green: 0.82, blue: 0.72), // teal
        Color(red: 0.95, green: 0.55, blue: 0.25), // orange
        Color(red: 0.95, green: 0.35, blue: 0.55), // pink
        Color(red: 0.30, green: 0.60, blue: 0.95), // blue
        Color(red: 0.85, green: 0.65, blue: 0.13), // gold
        Color(red: 0.55, green: 0.35, blue: 0.85), // light purple
        Color(red: 0.35, green: 0.80, blue: 0.60), // green
    ]
    
    private var groupColor: Color {
        let index = abs(workspace.id.hashValue) % Self.groupColors.count
        return Self.groupColors[index]
    }
    
    private var workspaceSessions: [ChatSession] {
        sessions.isEmpty ? appState.sidebarSessions(for: workspace) : sessions
    }
    
    private var activeSession: ChatSession? {
        workspaceSessions.first { $0.id == appState.selectedSession?.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group Row
            HStack(spacing: 8) {
                // Project avatar: its own favicon/logo when present, else the
                // colored # badge.
                ProjectAvatarView(
                    workspace: workspace,
                    fallbackColor: groupColor
                )
                
                // Name + chevron
                Button(action: {
                    let alreadySelected = appState.selectedWorkspace?.id == workspace.id
                    appState.selectWorkspace(workspace)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = SidebarExpansionLogic.nextState(
                            isAlreadySelected: alreadySelected,
                            isExpanded: isExpanded
                        )
                    }
                }) {
                    HStack(spacing: 4) {
                        if projectNeedsAttentionNow && !isExpanded {
                            AttentionBlinkDot()
                        }
                        Text(workspace.name)
                            .interfaceFont(size: 12, weight: .medium)
                            .foregroundColor(Color.mimo.textPrimary)
                            .lineLimit(1)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .interfaceFont(size: 9)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())
                
                Spacer(minLength: 0)
                
                // Session count
                Text("\(workspaceSessions.count)")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)

                // Pin: keep this project at the top of the sidebar.
                if isPinned || isHovered {
                    Button(action: { appState.toggleSidebarPin(id: SidebarPinID.project(workspace.id)) }) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .interfaceFont(size: 11)
                            .foregroundColor(isPinned ? Color.mimo.brand : Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(isPinned ? "Unpin project" : "Pin project to top")
                    .accessibilityIdentifier("sidebar.pinProject")
                }
                
                // Plus button
                Button(action: { appState.startNewTask(in: workspace) }) {
                    Image(systemName: "plus.circle")
                        .interfaceFont(size: 13)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locNewTask))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .onHover { hovering in isHovered = hovering }
            .onAppear(perform: refreshAttention)
            .onReceive(NotificationCenter.default.publisher(for: SidebarAttentionNotification.changed)) { _ in
                refreshAttention()
            }
            .onReceive(appState.$pendingQuestionRequest) { _ in
                refreshAttention()
            }
            
            // Nested Sessions
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if workspaceSessions.isEmpty {
                        Text(L.t(AppLocalizationKey.locTasksYet))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                            .padding(.leading, 50)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(workspaceSessions) { session in
                            SessionTaskRow(
                                session: session,
                                workspace: workspace,
                                groupColor: groupColor,
                                isHovered: hoveredSessionID == session.id
                            )
                            .onHover { hovering in
                                hoveredSessionID = hovering ? session.id : nil
                            }
                        }
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .task(id: workspace.id) {
            appState.loadSidebarSessions(for: workspace)
        }
        .onChange(of: appState.selectedWorkspace?.id) { newSelectionID in
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = SidebarExpansionLogic.stateAfterSelection(
                    workspaceID: workspace.id,
                    selectedID: newSelectionID,
                    isExpanded: isExpanded
                )
            }
        }
    }
}

/// A chat without a project. It is rendered as a top-level row — like a
/// project row, but with a chat icon — so project chats and project-less
/// chats never mix (F71).

struct NoProjectRow: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    private var isSelected: Bool {
        appState.isProjectlessMode
    }

    var body: some View {
        Button(action: { appState.selectNoProject() }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.mimo.brand.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.brand)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("No project"))
                        .interfaceFont(size: 12, weight: .medium)
                        .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                        .lineLimit(1)
                    Text(appState.toolWorkingDirectory)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.brand)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(isHovered ? Color.mimo.surfaceHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { isHovered = $0 }
        .help(L.t("Chats that are not tied to a project folder"))
        .accessibilityIdentifier("sidebar.noProject")
    }
}

/// Small spinner shown before a chat title while that chat's model turn is
/// still running, even when the user is reading another chat.

struct BackgroundActivityIndicator: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.mini)
            .scaleEffect(0.65)
            .frame(width: 10, height: 10)
            .help(L.t("The model is still answering in this chat"))
            .accessibilityLabel(L.t("The model is still answering in this chat"))
    }
}
