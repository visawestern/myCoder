import Foundation
import SwiftUI
import AppKit

/// Выбор рабочей области и чата.
extension AppState {
    
    func sessions(for workspace: Workspace) -> [ChatSession] {
        sessions
            .filter { $0.belongs(to: workspace) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Restore the last opened project at startup (user directive 2026-09-08).
    /// Pure resolution lives in WorkspaceRestoreLogic; this only wires the
    /// persisted id into `selectWorkspace` (which loads the project sessions).
    @MainActor
    func restoreLastWorkspace() {
        guard selectedWorkspace == nil else { return }
        let savedID = defaults.string(forKey: "com.mycoder.lastWorkspaceID")
        guard let workspace = WorkspaceRestoreLogic.restore(
            workspaces: workspaces,
            savedID: savedID
        ) else { return }
        selectWorkspace(workspace)
    }

    func selectWorkspace(_ workspace: Workspace, reloadSessions: Bool = true) {
        let previousID = selectedWorkspace?.id
        selectedWorkspace = workspace
        // User directive 2026-09-08: reopen the last project on app launch.
        defaults.set(workspace.id, forKey: "com.mycoder.lastWorkspaceID")
        restoreSpecWizardGate(for: workspace)
        // The synthetic "Chats" group is not a project: there is no project
        // database to load, so wiping here strands the list until the next
        // restart (the "+" on a project-less chat did exactly this). Merge
        // standalone rows synchronously instead.
        if workspace.id == ChatSession.standaloneProjectKey {
            selectedSession = nil
            sessions = DatabaseBridge.shared.loadStandaloneSessions()
            return
        }
        guard reloadSessions,
              WorkspaceSelectionLogic.shouldReloadSessions(previousID: previousID, newID: workspace.id) else {
            return
        }

        // Do not show the previous project's sessions while the new project's
        // database is loading. ChatPanel observes the nil selection and clears
        // its message store before the new session list arrives.
        selectedSession = nil
        sessions = []
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadSessionsFromDatabase(projectId: workspace.id)
        }
    }

    func selectSession(_ session: ChatSession) {
        // A sidebar cache can outlive the chat it points at (deleted through
        // the API, another window, or an older build). Selecting such a row
        // used to open a permanently empty chat; drop the row instead.
        let isInMemory = sessions.contains { $0.id == session.id }
        let existsInStore = isInMemory || DatabaseBridge.shared.sessionExists(id: session.id)
        if SessionSelectionGuardLogic.decision(
            sessionIsInMemory: isInMemory,
            sessionExistsInStore: existsInStore
        ) == .removeStaleRow {
            removeSessionFromInMemoryState(id: session.id)
            shellActionNotice = "This chat no longer exists — it was removed from the list."
            shellActionNoticeTone = .error
            MyCoderAPIServer.appendLog("🗑 removed stale sidebar chat: id=\(session.id)")
            return
        }
        if let workspace = workspaces.first(where: { session.belongs(to: $0) }) {
            selectWorkspace(workspace)
        }
        selectedSession = session
        restoreSelection(for: session)
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        refreshSubagentSessions()
        scheduleGitRefresh(sessionID: session.id)
        
        // Unarchive session if it was archived (so user can resume chatting)
        Task {
            try? DatabaseManager.shared.unarchiveSession(id: session.id)
        }
    }

    /// Reload the sub-agent list for the selected chat from its own store.
    func refreshSubagentSessions() {
        guard let session = selectedSession else {
            subagentSessions = []
            return
        }
        let projectKey = selectedWorkspace?.id ?? ChatSession.standaloneProjectKey
        subagentSessions = DatabaseBridge.shared.loadChildSessions(
            parentID: session.id,
            projectKey: projectKey
        )
    }
}
