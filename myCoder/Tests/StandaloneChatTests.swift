import Testing
import Foundation
@testable import myCoder

/// Audit 2026-09-08 (user directive): standalone chats — conversations that
/// do not belong to any workspace — must persist, appear in the sidebar's
/// "Chats" group, and never silently disappear.
@Suite("Standalone chats (no project)")
struct StandaloneChatTests {

    @MainActor
    private func makeAppState() -> AppState {
        let appState = AppState()
        appState.clearInMemoryState()
        return appState
    }

    @MainActor
    @Test func createdStandaloneSessionIsVisibleAndPersisted() {
        let appState = makeAppState()
        let before = appState.sessions.count

        let session = appState.createStandaloneSession(title: "  Quick question  ")

        #expect(session.directory == ChatSession.standaloneProjectKey)
        #expect(session.title == "Quick question")
        #expect(appState.sessions.count == before + 1)
        #expect(appState.standaloneSessions.contains { $0.id == session.id })
        // The persisted row must be loadable from the global DB.
        let loaded = DatabaseBridge.shared.loadStandaloneSessions()
        #expect(loaded.contains { $0.id == session.id })
    }

    @MainActor
    @Test func emptyTitleFallsBackToNewChat() {
        let appState = makeAppState()
        let session = appState.createStandaloneSession(title: "   ")
        #expect(session.title == "New Chat")
    }

    @MainActor
    @Test func standaloneSessionsExcludeProjectSessions() {
        let appState = makeAppState()
        appState.clearInMemoryState()
        let project = Workspace(id: "proj-1", name: "Proj", path: "/tmp/proj-1", tasks: [])
        appState.workspaces = [project]
        let inProject = ChatSession(id: "s-proj", title: "In project", directory: "/tmp/proj-1")
        let standalone = ChatSession(id: "s-free", title: "Free", directory: ChatSession.standaloneProjectKey)
        appState.sessions = [inProject, standalone]

        let ids = appState.standaloneSessions.map(\.id)
        #expect(ids == ["s-free"])
    }

    @MainActor
    @Test func loadMergesPersistedRowsWithoutDuplicates() {
        let appState = makeAppState()
        let created = appState.createStandaloneSession(title: "merge me")
        // Simulate a restart: empty in-memory list, then merge from DB.
        appState.sessions = []
        appState.loadStandaloneSessionsIntoState()
        #expect(appState.sessions.contains { $0.id == created.id })
        // Idempotent: second merge must not duplicate.
        appState.loadStandaloneSessionsIntoState()
        #expect(appState.sessions.filter { $0.id == created.id }.count == 1)
    }
}

/// User directive 2026-09-08: reopen the last worked-on project at launch.
@Suite("WorkspaceRestoreLogic (last project on launch)")
struct WorkspaceRestoreLogicTests {

    @Test func restoresSavedWorkspaceByID() {
        let a = Workspace(id: "a", name: "A", path: "/a", tasks: [])
        let b = Workspace(id: "b", name: "B", path: "/b", tasks: [])
        #expect(WorkspaceRestoreLogic.restore(workspaces: [a, b], savedID: "b")?.id == "b")
    }

    @Test func fallsBackToFirstWhenSavedMissing() {
        let a = Workspace(id: "a", name: "A", path: "/a", tasks: [])
        let b = Workspace(id: "b", name: "B", path: "/b", tasks: [])
        #expect(WorkspaceRestoreLogic.restore(workspaces: [a, b], savedID: "gone")?.id == "a")
    }

    @Test func nilSavedIDFallsBackToFirst() {
        let a = Workspace(id: "a", name: "A", path: "/a", tasks: [])
        #expect(WorkspaceRestoreLogic.restore(workspaces: [a], savedID: nil)?.id == "a")
    }

    @Test func emptyWorkspacesRestoreNil() {
        #expect(WorkspaceRestoreLogic.restore(workspaces: [], savedID: "a") == nil)
    }
}
