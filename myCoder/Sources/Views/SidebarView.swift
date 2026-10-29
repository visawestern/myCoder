import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewProjectMenu = false
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                SidebarActionRow(icon: SidebarLayout.newTaskIcon, label: L.t("New task"), shortcut: "⌘N") {
                    appState.startNewTask(in: appState.selectedWorkspace)
                }
                SidebarActionRow(icon: "bubble.left.and.bubble.right", label: L.t("New chat without a project")) {
                    appState.startProjectlessTask()
                }
                newProjectActionRow
                SidebarActionRow(icon: "folder", label: L.t(AppLocalizationKey.locOpenProject), shortcut: "⌘O") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Open"
                    panel.message = L.t(AppLocalizationKey.locSelectFolder)
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.addWorkspace(path: url.path)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            WorkspacesSectionHeader()
                .padding(.horizontal, 10)
                .padding(.top, 8)
            
            if appState.showWorkspaceSearchField {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                    TextField(L.t("Filter workspaces"), text: $appState.workspaceFilterQuery)
                        .zcodeTextFieldStyle()
                        .interfaceFont(size: 12)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The "no project" option: chats that are not tied to any
                    // project folder. It is the project picker's entry for the
                    // project-less mode and a shortcut to a project-less chat.
                    NoProjectRow()
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    if appState.workspaceViewMode == .grid {
                        if appState.workspacesSectionExpanded {
                            WorkspaceGridView(workspaces: appState.displayedWorkspaces)
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                        }
                        // A chat without a project keeps its own top-level row
                        // even in grid mode (F71), so it stays visible.
                        ForEach(appState.sidebarTreeItems) { item in
                            if case .projectlessChat(let node) = item {
                                ProjectlessChatRow(node: node)
                            }
                        }
                    } else {
                        // One tree, one pass: projects with their chats and
                        // every project-less chat as its own top-level row
                        // (F71). A chat can never show up twice.
                        ForEach(appState.sidebarTreeItems) { item in
                            switch item {
                            case .project(let node):
                                if appState.workspacesSectionExpanded {
                                    WorkspaceSidebarSection(
                                        workspace: node.workspace,
                                        sessions: node.sessions,
                                        isPinned: node.isPinned,
                                        startsExpanded: appState.selectedWorkspace?.id == node.id
                                    )
                                }
                            case .projectlessChat(let node):
                                ProjectlessChatRow(node: node)
                            }
                        }

                        if appState.displayedWorkspaces.isEmpty && appState.sidebarProjectlessSessions.isEmpty {
                            Text(appState.workspaces.isEmpty ? L.t("No workspaces") : "No matching workspaces")
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                        }
                    }
                }
            }
            
            SidebarFooterView()
        }
        .background(Color.mimo.backgroundAlt)
        .sheet(isPresented: $appState.showNotifications) {
            NotificationsSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showWorkspacesOverview) {
            WorkspacesOverviewSheet()
                .environmentObject(appState)
        }
    }
    
    private var newProjectActionRow: some View {
        Button {
            showNewProjectMenu.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .interfaceFont(size: 13)
                    .frame(width: 18)
                    .foregroundColor(Color.mimo.textSecondary)
                Text(L.t(AppLocalizationKey.locNewProject))
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Text("⌘⇧P")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                Image(systemName: "chevron.down")
                    .interfaceFont(size: 8, weight: .semibold)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(showNewProjectMenu ? Color.mimo.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t("Create an empty project or set up a project plan"))
        .popover(isPresented: $showNewProjectMenu, arrowEdge: .bottom) {
            NewProjectTypeMenu { mode in
                showNewProjectMenu = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    appState.beginProjectCreation(mode: mode)
                }
            }
            .environmentObject(appState)
        }
    }
}

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
        .help("Filter: \(appState.workspaceFilterPreset.rawValue)")
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
        .help("Toggle list/grid view")
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
                        Image(systemName: "folder.fill")
                            .interfaceFont(size: 18)
                            .foregroundColor(appState.selectedWorkspace?.id == workspace.id ? Color.mimo.brand : Color.mimo.textMuted)
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

struct SidebarFooterView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Text(appState.userInitials)
                    .interfaceFont(size: 11, weight: .semibold)
                    .foregroundColor(.white)
            }
            
            Text(appState.userDisplayName)
                .interfaceFont(size: 12, weight: .medium)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { appState.showNotifications = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.textSecondary)
                    
                    if appState.notificationService.unreadCount > 0 {
                        Text("\(appState.notificationService.unreadCount)")
                            .interfaceFont(size: 9, weight: .bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.mimo.error)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(HandCursorButtonStyle())
            .help("Notifications (\(appState.notificationService.unreadCount) unread)")
            
            Button(action: { appState.openSettings() }) {
                Image(systemName: "gearshape")
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.mimo.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.mimo.border)
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct NotificationsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L.t(AppLocalizationKey.locNotifications1))
                    .interfaceFont(size: 18, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                if appState.notificationService.unreadCount > 0 {
                    Button(L.t(AppLocalizationKey.locMarkAllRead)) {
                        appState.notificationService.markAllAsRead()
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.brand)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            .padding(20)
            
            Divider()
                .padding(.horizontal, 12)
            
            if appState.notificationService.notifications.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .interfaceFont(size: 32)
                        .foregroundColor(Color.mimo.textMuted.opacity(0.5))
                    Text(L.t(AppLocalizationKey.locNotifications))
                        .interfaceFont(size: 14)
                        .foregroundColor(Color.mimo.textSecondary)
                    Text(L.t(AppLocalizationKey.locTaskCompletionsAndSystemAlertsWillAppearHere))
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.notificationService.sortedNotifications) { notification in
                            NotificationRow(notification: notification)
                                .environmentObject(appState)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 380, height: 400)
        .background(Color.mimo.background)
    }
}

struct NotificationRow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let notification: AppNotification
    /// Guards against a host delivering both the row tap and the inner action
    /// button for the same click, which would route (and scroll) twice.
    @State private var lastRoutedAt = Date.distantPast
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.type.icon)
                .interfaceFont(size: 14)
                .foregroundColor(iconColor)
                .frame(width: 18)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title)
                        .interfaceFont(size: 12, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    if !notification.isRead {
                        Circle()
                            .fill(Color.mimo.brand)
                            .frame(width: 7, height: 7)
                    }
                    Text(timeAgo(notification.timestamp))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
                Text(notification.message)
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .lineLimit(2)
                
                if let action = notification.action {
                    Button(action: { handleAction(action) }) {
                        Text(actionLabel(action))
                            .interfaceFont(size: 11, weight: .medium)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.notificationService.markAsRead(notification.id)
            // Tapping the alert body is the same intent as its action button:
            // open the chat (and the exact tool call, when anchored).
            if let action = notification.action {
                handleAction(action)
            }
        }
        .background(
            notification.isRead
                ? Color.clear
                : Color.mimo.brand.opacity(0.04)
        )
        
        Divider()
            .padding(.leading, 42)
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .info: return Color.mimo.brand
        case .success: return Color.mimo.success
        case .warning: return Color.mimo.warning
        case .error: return Color.mimo.error
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
    
    private func actionLabel(_ action: NotificationAction) -> String {
        switch action {
        case .openSession: return "Open Session"
        case .openMessage: return "Open tool call"
        case .openSettings: return "Open Settings"
        case .openGit: return "View Changes"
        case .custom(let id): return id
        }
    }
    
    private func handleAction(_ action: NotificationAction) {
        let now = Date()
        guard now.timeIntervalSince(lastRoutedAt) > 0.3 else { return }
        lastRoutedAt = now
        // Child buttons do not reliably propagate the row tap gesture on every
        // macOS SwiftUI host, so action routing explicitly marks the item read.
        appState.notificationService.markAsRead(notification.id)
        let sessionWasFound: Bool
        switch action {
        case .openSession(let sessionID):
            guard let session = appState.sessionForNavigation(id: sessionID) else {
                return
            }
            appState.selectSession(session)
            sessionWasFound = true
        case .openMessage(let sessionID, let messageID):
            // Open the chat AND ask the panel to scroll to the message that
            // raised the alert — opening at the newest message hid the card.
            guard let session = appState.sessionForNavigation(id: sessionID) else {
                return
            }
            appState.selectSession(session)
            appState.requestMessageFocus(sessionID: sessionID, messageID: messageID)
            sessionWasFound = true
        case .openSettings:
            appState.openSettings()
            sessionWasFound = false
        case .openGit:
            appState.showGoal = true
            sessionWasFound = false
        case .custom:
            sessionWasFound = false
        }
        if NotificationActionRoutingLogic.shouldDismissSheet(
            after: action,
            sessionWasFound: sessionWasFound
        ) {
            dismiss()
        }
    }
}

struct WorkspacesOverviewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    private var filtered: [Workspace] {
        SidebarWorkspaceLogic.filtered(appState.workspaces, query: query)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locOverview))
                    .interfaceFont(size: 18, weight: .semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locSearchWorkspaces), text: $query)
                    .zcodeTextFieldStyle()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // The "no project" entry of the project picker.
                    Button(action: {
                        appState.selectNoProject()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundColor(Color.mimo.brand)
                            Text(L.t("No project"))
                                .foregroundColor(Color.mimo.textPrimary)
                            Spacer()
                            if appState.isProjectlessMode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.mimo.brand)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(HandCursorButtonStyle())

                    Divider()
                        .padding(.vertical, 4)

                    ForEach(filtered) { workspace in
                        Button(action: {
                            appState.selectWorkspace(workspace)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(Color.mimo.textMuted)
                                Text(workspace.name)
                                    .foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                if appState.selectedWorkspace?.id == workspace.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.mimo.brand)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(HandCursorButtonStyle())
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
        .background(Color.mimo.background)
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
                // Colored circle avatar with #
                ZStack {
                    Circle()
                        .fill(groupColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Text("#")
                        .interfaceFont(size: 12, weight: .bold)
                        .foregroundColor(groupColor)
                }
                
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
                    selectedID: newSelectionID
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

struct ProjectlessChatRow: View {
    let node: SidebarProjectlessChatNode
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    private var isSelected: Bool {
        appState.selectedSession?.id == node.id
    }

    private var timeBadge: String {
        let interval = Date().timeIntervalSince(node.session.updatedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.mimo.cyan.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "bubble.left")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.cyan)
            }

            Button(action: { appState.selectSession(node.session) }) {
                HStack(spacing: 6) {
                    if appState.streamingSessionIDs.contains(node.id) {
                        BackgroundActivityIndicator()
                    }
                    Text(node.title)
                        .interfaceFont(size: 12, weight: .medium)
                        .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(isSelected ? L.t(AppLocalizationKey.locNow) : timeBadge)
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .accessibilityIdentifier("sidebar.projectlessChat")

            if node.isPinned || isHovered {
                Button(action: { appState.toggleSidebarPin(id: SidebarPinID.chat(node.id)) }) {
                    Image(systemName: node.isPinned ? "pin.fill" : "pin")
                        .interfaceFont(size: 11)
                        .foregroundColor(node.isPinned ? Color.mimo.brand : Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(node.isPinned ? "Unpin chat" : "Pin chat to top")
                .accessibilityIdentifier("sidebar.pinChat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .onHover { hovering in isHovered = hovering }
    }
}

struct SessionTaskRow: View {
    let session: ChatSession
    let workspace: Workspace
    let groupColor: Color
    var isHovered: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var isRenaming = false
    @FocusState private var isRenameFocused: Bool
    @State private var showingDeleteConfirm = false
    @State private var renameText = ""

    private func commitRename() {
        isRenaming = false
        appState.renameSessionInDatabaseUI(id: session.id, title: renameText)
    }
    
    var isSelected: Bool {
        appState.selectedSession?.id == session.id
    }
    
    private var timeBadge: String {
        let interval = Date().timeIntervalSince(session.updatedAt)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Color indicator strip (only for selected)
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(groupColor)
                    .frame(width: 2)
            } else {
                Color.clear
                    .frame(width: 2)
            }
            
            // Session content
            if isRenaming {
                HStack(spacing: 6) {
                    TextField("Chat title", text: $renameText)
                        .textFieldStyle(.plain)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textPrimary)
                        .focused($isRenameFocused)
                        .onAppear { isRenameFocused = true }
                        .onSubmit(commitRename)
                        .onChange(of: isRenameFocused) { focused in
                            if !focused, isRenaming { commitRename() }
                        }
                        .onExitCommand { isRenaming = false }

                    Button(action: commitRename) {
                        Image(systemName: "checkmark")
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.cyan)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help("Save title")

                    Button(action: { isRenaming = false }) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help("Cancel rename")
                }
            } else {
                Button(action: { appState.selectSession(session) }) {
                    HStack(spacing: 6) {
                        if appState.streamingSessionIDs.contains(session.id) {
                            BackgroundActivityIndicator()
                        }
                        Text(session.title)
                            .interfaceFont(size: 12)
                            .foregroundColor(isSelected ? Color.mimo.textPrimary : Color.mimo.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            // "now" badge
                            Text(L.t(AppLocalizationKey.locNow))
                                .interfaceFont(size: 9, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.mimo.textPrimary.opacity(0.12))
                                .cornerRadius(4)
                        } else {
                            // Time badge
                            Text(timeBadge)
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.textMuted)
                        }
                    }
                }
                .buttonStyle(HandCursorButtonStyle())
            }
            
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: { appState.startNewTask(in: workspace) }) {
                        Image(systemName: "plus")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    
                    Menu {
                        Button("Rename…") {
                            renameText = session.title
                            isRenaming = true
                        }
                        ShareLink(item: appState.sessionTranscriptMarkdown(sessionId: session.id) ?? session.title) {
                            Text("Share transcript")
                        }
                        Button("Export transcript…") {
                            appState.exportSessionTranscript(sessionId: session.id)
                        }
                        Divider()
                        if SessionRowActions.showInFinderURL(session: session, workspace: workspace) != nil {
                            Button(L.t(AppLocalizationKey.locShowInFinder)) {
                                appState.openFolderInFinder(session.directory.isEmpty ? workspace.path : session.directory)
                            }
                        }
                        Button(L.t(AppLocalizationKey.locNewTaskSidebar)) {
                            appState.startNewTask(in: workspace)
                        }
                        Button(L.t(AppLocalizationKey.locArchive)) {
                            appState.archiveSessionInDatabaseUI(id: session.id)
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.vertical")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.leading, 50)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? Color.mimo.textPrimary.opacity(0.06)
                : Color.clear
        )
        .cornerRadius(6)
        .alert("Delete this chat?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                appState.deleteSessionInDatabaseUI(id: session.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the chat and its messages from the local database. It cannot be undone.")
        }
    }
}

/// Sidebar group for standalone chats — conversations that do not belong to
/// any project (audit 2026-09-08, user directive: such chats used to disappear
/// because nothing listed them). Persisted in the global DB; synthetic
/// workspace keeps SessionTaskRow happy.
struct SearchPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    private var matchingSessions: [ChatSession] {
        SearchPaletteLogic.matchingSessions(appState.sessions, query: query)
    }

    private var matchingFiles: [FileIndexRecord] {
        appState.searchProjectFiles(query: query)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t(AppLocalizationKey.locSearch))
                    .interfaceFont(size: 20, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help("Close (Esc)")
            }

            TextField(L.t(AppLocalizationKey.locSearchTasks), text: $query)
                .zcodeTextFieldStyle()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(matchingSessions) { session in
                        Button(action: {
                            appState.selectSession(session)
                            dismiss()
                        }) {
                            HStack {
                                Text(session.title)
                                    .interfaceFont(size: 13)
                                    .foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                Text(session.durationLabel)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textMuted)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HandCursorButtonStyle())
                    }

                    if !matchingFiles.isEmpty {
                        Text(L.t(AppLocalizationKey.locProjectFiles))
                            .interfaceFont(size: 11, weight: .semibold)
                            .foregroundColor(Color.mimo.textMuted)
                            .padding(.top, 8)
                        ForEach(matchingFiles, id: \.path) { file in
                            Button(action: {
                                guard let root = appState.selectedWorkspace?.path else { return }
                                let url = URL(fileURLWithPath: root).appendingPathComponent(file.path)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(Color.mimo.textMuted)
                                    Text(file.path)
                                        .interfaceFont(size: 12)
                                        .foregroundColor(Color.mimo.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(file.language)
                                        .interfaceFont(size: 10)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HandCursorButtonStyle())
                        }
                    }
                }
            }

            Text(L.t(AppLocalizationKey.locEscClose))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
        .padding(24)
        .frame(width: 480, height: 400)
        .background(Color.mimo.background)
        .onExitCommand {
            dismiss()
        }
    }
}

// MARK: - Archived projects popover (plan Раздел 11 Блок 2 п.16 + Раздел 8)

struct ArchivedProjectsPopover: View {
    @EnvironmentObject var appState: AppState
    @State private var archived: [ProjectRegistryEntry] = ProjectRegistryLogic.archived(
        ProjectRegistryStore.load()
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t(AppLocalizationKey.locArchivedProjects))
                .interfaceFont(size: 13, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)

            if archived.isEmpty {
                Text(L.t(AppLocalizationKey.locArchivedProjects1))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            } else {
                ForEach(archived) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textMuted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .interfaceFont(size: 12, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            Text(entry.path)
                                .interfaceFont(size: 10)
                                .foregroundColor(Color.mimo.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(L.t(AppLocalizationKey.locRestore)) { restore(entry) }
                            .interfaceFont(size: 11)
                            .buttonStyle(HandCursorButtonStyle())
                            .foregroundColor(Color.mimo.brand)
                    }
                }
            }

            Divider()
            Button(action: {
                appState.showArchivePopover = false
                appState.showSettings = true
                appState.settingsTab = .storage
            }) {
                Text(L.t(AppLocalizationKey.locOpenFullStoragePanel))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
        }
        .padding(14)
        .frame(width: 320)
    }

    private func restore(_ entry: ProjectRegistryEntry) {
        try? ProjectRegistryStore.restore(id: entry.id)
        appState.refreshProjectRegistry()
        archived = ProjectRegistryLogic.archived(ProjectRegistryStore.load())
    }
}
