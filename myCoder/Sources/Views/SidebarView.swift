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














