import Foundation
import SwiftUI
import AppKit

/// Жизненный цикл чатов.
extension AppState {
    func applySessionPlan(from serverMessages: [MimoMessageResponse]) {
        let steps = SessionPlanParser.steps(from: serverMessages)
        if !steps.isEmpty {
            currentSteps = steps
        }
    }

    func startNewTask(in workspace: Workspace? = nil) {
        if let workspace {
            selectWorkspace(workspace)
        }
        selectedSession = nil
        selectedTask = nil
        isLoading = false
        isStreaming = false
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        showGoal = false
        inputFocusRequest += 1
    }

    /// Create the local project-scoped session required before the first user
    /// or assistant message is appended. Serve used to create its remote
    /// session later, which meant the earlier MessageStore.append calls saw a
    /// nil currentSessionID and silently skipped local persistence.
    @MainActor
    // MARK: - Standalone chats (no project)

    /// Synthetic workspace representing the sidebar "Chats" group: every
    /// conversation that does not belong to a real project directory.
    var standaloneWorkspace: Workspace {
        Workspace(
            id: ChatSession.standaloneProjectKey,
            name: L.t("Chats"),
            path: ChatSession.standaloneProjectKey,
            tasks: []
        )
    }

    /// True when the app works without a project — a chat that is not tied to
    /// any project folder.
    var isProjectlessMode: Bool {
        ProjectlessWorkspaceLogic.isProjectless(selectedWorkspace)
    }

    /// Working directory of the open chat: the project folder for a project
    /// chat, the home folder for a project-less one. Every tool call, shell
    /// command and file read is resolved against it.
    var toolWorkingDirectory: String {
        ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: selectedSession?.directory,
            workspacePath: selectedWorkspace?.path
        )
    }

    /// Switch to the "no project" mode: chats are not tied to a project folder.
    @MainActor
    func selectNoProject() {
        selectWorkspace(standaloneWorkspace)
    }

    /// Start a new chat without a project.
    @MainActor
    func startProjectlessTask() {
        selectNoProject()
        startNewTask(in: standaloneWorkspace)
    }

    /// Conversations that belong to no workspace (audit 2026-09-08). New
    /// standalone chats carry the reserved directory key; legacy in-flight
    /// API chats (temp directory, never persisted) match the "no workspace"
    /// branch so they remain visible until the app restarts.
    var standaloneSessions: [ChatSession] {
        sessions
            .filter { session in
                if session.directory == ChatSession.standaloneProjectKey { return true }
                return !workspaces.contains { session.belongs(to: $0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Create a persisted chat that BELONGS to the open project.
    ///
    /// `/api/send` without a chatId used to always create a standalone chat,
    /// so an open project was ignored and the model was told its working
    /// directory was the home folder while the context pack listed project
    /// files (live run 2026-11-03). The chat now carries the project directory,
    /// so `toolWorkingDirectory` resolves to the project and the system prompt
    /// reports the real `cwd`.
    @MainActor
    @discardableResult
    func createProjectSession(in workspace: Workspace, title: String) -> ChatSession {
        let sessionID = UUID().uuidString
        let sessionTitle = ChatTitleLogic.title(for: title, existingTitles: sessions.map(\.title))
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: workspace.id,
            title: sessionTitle,
            directory: workspace.path,
            branch: nil,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        let session = ChatSession(
            id: sessionID,
            title: sessionTitle,
            directory: workspace.path,
            modelID: selectedModel.isEmpty ? nil : selectedModel,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        MyCoderAPIServer.appendLog(
            "📝 createProjectSession: id=\(sessionID), dir=\(workspace.path), title=\(sessionTitle)"
        )
        return session
    }

    /// Create a persisted standalone chat: stored in the global database
    /// under the reserved `standalone` project key, inserted into the
    /// in-memory list, NOT selected (caller decides).
    @MainActor
    @discardableResult
    func createStandaloneSession(title: String) -> ChatSession {
        let sessionID = UUID().uuidString
        let sessionTitle = ChatTitleLogic.title(for: title, existingTitles: sessions.map(\.title))
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: ChatSession.standaloneProjectKey,
            title: sessionTitle,
            directory: ChatSession.standaloneProjectKey,
            branch: nil,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        let session = ChatSession(
            id: sessionID,
            title: sessionTitle,
            directory: ChatSession.standaloneProjectKey,
            modelID: selectedModel.isEmpty ? nil : selectedModel,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        MyCoderAPIServer.appendLog("📝 createStandaloneSession: id=\(sessionID), title=\(sessionTitle)")
        return session
    }

    /// Put a chat into the sidebar caches so a freshly created chat shows up
    /// right away.
    ///
    /// The sidebar keeps its own per-project cache; a chat that only lands in
    /// the in-memory list stays invisible there until the project is reloaded
    /// — which is why a new chat could not be found in the list.
    @MainActor
    func registerSessionInSidebar(_ session: ChatSession) {
        if let workspace = workspaces.first(where: { session.belongs(to: $0) }) {
            var projectSessions = sidebarProjectSessions[workspace.id] ?? []
            projectSessions.removeAll { $0.id == session.id }
            projectSessions.insert(session, at: 0)
            sidebarProjectSessions[workspace.id] = projectSessions
            return
        }
        var projectless = sidebarProjectlessSessions
        projectless.removeAll { $0.id == session.id }
        projectless.insert(session, at: 0)
        sidebarProjectlessSessions = projectless
    }

    /// Drop a deleted/archived chat from every in-memory list the sidebar
    /// renders. Deleting used to touch `sessions` only, leaving the sidebar's
    /// own caches holding rows whose history no longer existed — clicking one
    /// opened an empty chat.
    func removeSessionFromInMemoryState(id: String) {
        sessions = SidebarSessionRemovalLogic.removing(id: id, from: sessions)
        sidebarProjectSessions = SidebarSessionRemovalLogic.removing(
            id: id,
            from: sidebarProjectSessions
        )
        sidebarProjectlessSessions = SidebarSessionRemovalLogic.removing(
            id: id,
            from: sidebarProjectlessSessions
        )
        pinnedSidebarItemIDs.remove(SidebarPinID.chat(id))
        streamingSessionIDs.remove(id)
        if selectedSession?.id == id {
            selectedSession = nil
        }
        if messageFocusRequest?.sessionID == id {
            messageFocusRequest = nil
        }
    }

    /// Resolve a chat for notification/deep-link navigation, materializing it
    /// from a sidebar cache or the database when it is not in `sessions`.
    @MainActor
    func sessionForNavigation(id: String) -> ChatSession? {
        if let session = sessions.first(where: { $0.id == id }) {
            return session
        }
        if let cached = sidebarKnownSessions.first(where: { $0.id == id }) {
            return cached
        }
        return materializeSessionFromDatabase(id: id)
    }

    /// Ask the chat panel to scroll to one concrete message. The token makes
    /// repeated taps on the same notification trigger a fresh scroll.
    @MainActor
    func requestMessageFocus(sessionID: String, messageID: String) {
        messageFocusRequest = MessageFocusRequest(
            sessionID: sessionID,
            messageID: messageID
        )
    }

    /// Consume a focus request once the chat panel applied it.
    @MainActor
    func clearMessageFocus(id: UUID) {
        guard messageFocusRequest?.id == id else { return }
        messageFocusRequest = nil
    }

    /// Merge persisted standalone chats into the in-memory list at startup
    /// (audit 2026-09-08 — they used to vanish after every restart).
    @MainActor
    func loadStandaloneSessionsIntoState() {
        let stored = DatabaseBridge.shared.loadStandaloneSessions()
        guard !stored.isEmpty else { return }
        let existing = Set(sessions.map(\.id))
        let missing = stored.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        sessions.append(contentsOf: missing)
        updateSidebarProjectlessSessions(stored)
        MyCoderAPIServer.appendLog("📝 loadStandaloneSessionsIntoState: +\(missing.count) standalone chats")
    }

    /// Materialize one persisted session into state by id (audit 2026-09-09):
    /// API/UI requests arriving during startup (or addressing a chat that was
    /// never merged into memory) must resolve to the STORED chat instead of
    /// spawning a duplicate. Returns the session when found in memory or in
    /// the standalone store.
    @MainActor
    @discardableResult
    func materializeSessionFromDatabase(id: String) -> ChatSession? {
        if let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        if let stored = DatabaseBridge.shared.loadStandaloneSessions().first(where: { $0.id == id }) {
            sessions.insert(stored, at: 0)
            registerSessionInSidebar(stored)
            MyCoderAPIServer.appendLog("📝 materializeSessionFromDatabase: +\(id)")
            return stored
        }
        return nil
    }

    @MainActor
    func prepareLocalSessionForSend(title: String) -> String? {
        if let selectedID = selectedSession?.id {
            return selectedID
        }
        return createLocalSessionForSend(title: title)
    }

    /// Always creates a fresh chat in the selected workspace (or a standalone
    /// chat when none is selected). Used by spec-node coding, which must not
    /// reuse whatever chat happened to be open.
    @MainActor
    func createLocalSessionForSend(title: String) -> String? {
        // Audit 2026-09-08: a chat started with NO workspace selected is a
        // standalone chat — it must persist and stay visible in the sidebar's
        // Chats group (user directive: standalone chats kept disappearing).
        guard let workspace = selectedWorkspace else {
            let session = createStandaloneSession(title: title)
            return session.id
        }
        let sessionID = UUID().uuidString
        let sessionTitle = ChatTitleLogic.title(for: title, existingTitles: sessions.map(\.title))
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: workspace.path,
            title: sessionTitle,
            directory: workspace.path,
            branch: workspace.branch,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        let session = ChatSession(
            id: sessionID,
            title: sessionTitle,
            directory: workspace.path,
            branch: workspace.branch,
            modelID: selectedModel.isEmpty ? nil : selectedModel,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        return sessionID
    }

    func openSkillsSettings() {
        settingsTab = .skills
        showSettings = true
    }

    func openFolderInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    func openSettings() {
        showSettings = true
    }

    @MainActor
    func upsertSession(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        selectedSession = session
        MyCoderAPIServer.appendLog("📝 upsertSession: id=\(session.id), sessions=\(sessions.count), selected=\(selectedSession?.id ?? "nil")")
    }

    @MainActor
    func registerSessionFromServer(id: String, title: String, directory: String, select: Bool = true) {
        let session = ChatSession(
            id: id,
            title: title,
            directory: directory,
            branch: selectedWorkspace?.branch
        )
        if select {
            upsertSession(session)
        } else if !sessions.contains(where: { $0.id == id }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
    }
}
