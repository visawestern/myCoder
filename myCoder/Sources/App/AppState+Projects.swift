import Foundation
import SwiftUI
import AppKit

/// Создание проектов и мастер спецификации.
extension AppState {
    
    @discardableResult
    @MainActor
    func addWorkspace(path: String, branch: String? = nil) -> Workspace {
        let normalized = ChatSession.normalizedPath(path)
        if let existing = workspaces.first(where: { ChatSession.normalizedPath($0.path) == normalized }) {
            createOrUpdateProject(id: existing.id, name: existing.name, path: normalized, gitBranch: existing.branch)
            selectWorkspace(existing)
            return existing
        }
        
        // Round 14 (п.17/п.18): a project's id is its canonical path — never a
        // fresh UUID, so the DB row, registry entry, sessions and navigation
        // all agree on ONE identity (the old code minted a second UUID here).
        let workspace = Workspace(
            id: ProjectIdentityLogic.projectID(for: normalized),
            name: (normalized as NSString).lastPathComponent,
            path: normalized,
            branch: branch,
            tasks: []
        )
        workspaces.append(workspace)
        selectWorkspace(workspace, reloadSessions: false)
        // The database row IS the registration: Storage/Sidebar read the
        // `projects` table, so no side registry needs to be updated here.
        createOrUpdateProject(id: workspace.id, name: workspace.name, path: normalized, gitBranch: branch)
        return workspace
    }

    /// Создать новый проект: добавляет workspace и сохраняет в БД
    @MainActor
    func createNewProject(name: String, path: String) {
        let normalizedPath = ChatSession.normalizedPath(path)
        // Round 14 (п.18): the id must be the canonical path (same as
        // addWorkspace), NOT a random UUID — the two callers used to emit two
        // different ids for the same folder.
        let projectId = ProjectIdentityLogic.projectID(for: normalizedPath)
        
        // Сохраняем в БД
        createOrUpdateProject(id: projectId, name: name, path: normalizedPath)
        
        // Clear any stale wizard draft from a previous project at this path
        DatabaseBridge.shared.clearSpecWizardDraft(projectPath: normalizedPath)
        
        // Evict any stale wizard session for this path so a new project
        // gets a fresh session (not a cached session from a previous project
        // at the same location).
        SpecWizardSessionStore.shared.evict(projectPath: normalizedPath)
        
        // Добавляем workspace если его ещё нет (addWorkspace also registers
        // the project in the registry — Round 14 п.11).
        addWorkspace(path: normalizedPath)
    }

    // MARK: - Spec wizard entry

    /// A wizard draft stored in the project database re-opens the wizard when
    /// the project is selected again (including after an app restart). Forced
    /// or completed drafts never block chat.
    func restoreSpecWizardGate(for workspace: Workspace) {
        guard workspace.id != ChatSession.standaloneProjectKey else { return }
        let path = ChatSession.normalizedPath(workspace.path)
        Task { @MainActor in
            guard !self.dismissedSpecWizardPaths.contains(path) else { return }
            guard let draft = DatabaseBridge.shared.loadSpecWizardDraft(projectPath: path) else { return }
            guard self.selectedWorkspace.map({ ChatSession.normalizedPath($0.path) }) == path else { return }
            if draft.status == .draft {
                self.activeSpecWizardProjectPath = path
            } else if self.activeSpecWizardProjectPath == path {
                self.activeSpecWizardProjectPath = nil
            }
        }
    }

    func beginProjectCreation(mode: ProjectCreationMode) {
        projectCreationMode = mode
        showProjectCreation = true
    }

    func openSpecWizard(for projectPath: String) {
        let path = ChatSession.normalizedPath(projectPath)
        dismissedSpecWizardPaths.remove(path)
        activeSpecWizardProjectPath = path
    }

    /// Creates a dedicated chat for the next runnable task, links it to the
    /// node, and queues the coder prompt. The prompt is sent by ChatPanelView
    /// after the new chat's history has loaded, so it cannot race the load and
    /// disappear. Returns nil (and leaves the node pending) on failure.
    @MainActor
    @discardableResult
    func startSpecNodeCoding(wizard: SpecWizardSession, node: ProjectSpecNode) -> ChatSession? {
        let path = ChatSession.normalizedPath(wizard.projectPath)
        guard let workspace = workspaces.first(where: {
            ChatSession.normalizedPath($0.path) == path
        }) else {
            wizard.errorMessage = "Project workspace not found"
            return nil
        }
        if selectedWorkspace?.id != workspace.id {
            selectWorkspace(workspace)
        }
        let title = "\(node.externalKey) · \(node.title)"
        guard let sessionID = createLocalSessionForSend(title: title) else {
            wizard.errorMessage = "Could not create a coding chat"
            return nil
        }
        guard let prompt = wizard.startCoding(nodeID: node.id, sessionID: sessionID),
              let chat = sessions.first(where: { $0.id == sessionID }) else {
            _ = DatabaseBridge.shared.deleteSession(id: sessionID)
            sessions.removeAll { $0.id == sessionID }
            return nil
        }
        selectSession(chat)
        if wizard.draft.status == .draft {
            // Starting a task means the plan is accepted; keep the finished
            // project from re-gating chat after a relaunch.
            _ = wizard.finishWizard(forced: false)
        }
        pendingSpecNodePrompt = PendingSpecNodePrompt(
            id: UUID().uuidString,
            sessionID: sessionID,
            text: prompt
        )
        finishSpecWizard(for: wizard.projectPath)
        return chat
    }

    /// Reopens the chat linked to a task. Returns nil when the task was never
    /// started or its chat no longer exists.
    @MainActor
    @discardableResult
    func openSpecNodeChat(wizard: SpecWizardSession, nodeID: String) -> ChatSession? {
        guard let link = wizard.nodeSessions(for: nodeID).last else {
            wizard.errorMessage = "Coding chat not found"
            return nil
        }
        let path = ChatSession.normalizedPath(wizard.projectPath)
        let stored = DatabaseBridge.shared.loadSessions(projectId: path)
            .first(where: { $0.id == link.sessionID })
        guard let chat = sessions.first(where: { $0.id == link.sessionID })
                ?? stored
                ?? materializeSessionFromDatabase(id: link.sessionID) else {
            wizard.errorMessage = "Coding chat not found"
            return nil
        }
        selectSession(chat)
        finishSpecWizard(for: wizard.projectPath)
        return chat
    }

    func finishSpecWizard(for projectPath: String) {
        let path = ChatSession.normalizedPath(projectPath)
        dismissedSpecWizardPaths.insert(path)
        if activeSpecWizardProjectPath == path {
            activeSpecWizardProjectPath = nil
        }
    }
}
