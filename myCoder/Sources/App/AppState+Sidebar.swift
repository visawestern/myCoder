import Foundation
import SwiftUI
import AppKit

/// Сайдбар: рабочие области, чаты, закрепление.
extension AppState {
    
    var displayedWorkspaces: [Workspace] {
        let visible = WorkspaceArchiveVisibilityLogic.visible(
            workspaces,
            registry: projectRegistryEntries,
            selectedPath: selectedWorkspace?.path
        )
        let known = sidebarKnownSessions
        let nameFiltered = SidebarWorkspaceLogic.filtered(visible, query: workspaceFilterQuery)
        let sessionFiltered = SidebarWorkspaceLogic.filteredBySessionCount(nameFiltered, sessions: known, preset: workspaceFilterPreset)
        return SidebarWorkspaceLogic.sorted(sessionFiltered, order: workspaceSortOrder, sessions: known)
    }

    /// Every chat the sidebar knows about: all projects' chats plus the
    /// project-less ones. Used for the sidebar's filters and sorting, so a
    /// non-selected project is not counted as empty (F71).
    var sidebarKnownSessions: [ChatSession] {
        var byID: [String: ChatSession] = [:]
        for session in sessions { byID[session.id] = session }
        for projectSessions in sidebarProjectSessions.values {
            for session in projectSessions { byID[session.id] = session }
        }
        for session in sidebarProjectlessSessions { byID[session.id] = session }
        return Array(byID.values)
    }

    /// The sidebar tree: projects (with their chats) plus one top-level row
    /// per chat without a project. Built in a single pass so every chat has
    /// exactly one parent (F71).
    var sidebarTreeItems: [SidebarTreeItem] {
        SidebarTreeBuilder.build(
            workspaces: displayedWorkspaces,
            sessionsByWorkspaceID: sidebarProjectSessions,
            projectlessSessions: sidebarProjectlessSessions,
            pinnedIDs: pinnedSidebarItemIDs
        )
    }

    /// Chats of one project for the sidebar. The selected project answers
    /// from the in-memory list, other projects from their own database.
    func sidebarSessions(for workspace: Workspace) -> [ChatSession] {
        if let cached = sidebarProjectSessions[workspace.id] {
            return cached
        }
        return sessions.filter { $0.belongs(to: workspace) }
    }

    /// Load one project's chats for the sidebar (once per project).
    @MainActor
    func loadSidebarSessions(for workspace: Workspace) {
        guard sidebarProjectSessions[workspace.id] == nil else { return }
        let path = workspace.path
        let id = workspace.id
        Task { @MainActor in
            let loaded = DatabaseBridge.shared.loadSessions(projectId: path)
            sidebarProjectSessions[id] = loaded
        }
    }

    /// Clear all cached sidebar chats. Used after a full database reset so the
    /// sidebar cannot keep showing chats that no longer exist (bug report
    /// 2026-10-30).
    @MainActor
    func clearSidebarSessionCaches() {
        sidebarProjectSessions = [:]
        sidebarProjectlessSessions = []
    }

    /// Store one project's chats for the sidebar tree.
    @MainActor
    func updateSidebarSessions(projectID: String, sessions: [ChatSession]) {
        sidebarProjectSessions[projectID] = sessions
    }

    /// Store the chats that belong to no project.
    @MainActor
    func updateSidebarProjectlessSessions(_ sessions: [ChatSession]) {
        sidebarProjectlessSessions = sessions
    }

    /// Reload the chats that belong to no project.
    @MainActor
    func refreshSidebarProjectlessSessions() {
        sidebarProjectlessSessions = DatabaseBridge.shared.loadStandaloneSessions()
    }

    /// Pin or unpin a sidebar row (project or project-less chat).
    @MainActor
    func toggleSidebarPin(id: String) {
        if pinnedSidebarItemIDs.contains(id) {
            pinnedSidebarItemIDs.remove(id)
        } else {
            pinnedSidebarItemIDs.insert(id)
        }
        SidebarPinStore.save(pinnedSidebarItemIDs, defaults: defaults)
    }

    /// Reload the global project registry after Storage/Archive mutations so
    /// the sidebar reflects the action immediately instead of requiring a
    /// relaunch. Unknown registry rows remain non-destructive to workspaces.
    @MainActor
    func refreshProjectRegistry() {
        projectRegistryEntries = ProjectRegistryStore.load()
    }

    var userDisplayName: String { UserProfileDisplay.displayName() }

    var userInitials: String { UserProfileDisplay.initials(from: userDisplayName) }
}
