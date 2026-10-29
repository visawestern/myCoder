import Testing
import Foundation
@testable import myCoder

/// A newly created chat must show up in the sidebar right away — in its
/// project or, for a chat without a project, as its own top-level row.
@Suite("New chats appear in the sidebar")
struct NewChatSidebarVisibilityTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-sidebar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @MainActor
    @Test func projectChatIsListedUnderItsProject() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
        }

        let appState = AppState()
        appState.clearInMemoryState()
        let workspace = appState.addWorkspace(path: projectPath)

        // The sidebar caches a project's chats. The cache must not hide a
        // chat that was created afterwards.
        appState.updateSidebarSessions(projectID: workspace.id, sessions: [])

        let sessionID = appState.createLocalSessionForSend(title: "Fresh chat")

        let listed = appState.sidebarSessions(for: workspace)
        #expect(listed.contains { $0.id == sessionID },
                "A new chat must be visible in the sidebar of its project")
    }

    @MainActor
    @Test func projectlessChatIsListedAsItsOwnRow() throws {
        let appState = AppState()
        appState.clearInMemoryState()

        appState.startProjectlessTask()
        // The sidebar caches the project-less chats too.
        appState.updateSidebarProjectlessSessions([])
        let sessionID = appState.createLocalSessionForSend(title: "Loose chat")

        #expect(appState.sidebarProjectlessSessions.contains { $0.id == sessionID },
                "A chat without a project must be visible in the sidebar")
    }

    @MainActor
    @Test func addWorkspaceUsesIsolatedRegistryHomeDuringTests() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
        }

        let appState = AppState()
        appState.clearInMemoryState()
        let workspace = appState.addWorkspace(path: projectPath)

        // Regression: tests used to write temp sidebar projects into the real
        // ~/.mycoder/projects.json. The registry root must be sandboxed.
        #expect(appState.registryHomeDirectory.path.hasPrefix(
            FileManager.default.temporaryDirectory.path
        ))
        let entries = ProjectRegistryStore.load()
        #expect(entries.contains { $0.id == workspace.id })
        #expect(entries.contains { $0.path == ChatSession.normalizedPath(projectPath) })
    }

    @MainActor
    @Test func upsertedChatIsListedUnderItsProject() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
        }

        let appState = AppState()
        appState.clearInMemoryState()
        let workspace = appState.addWorkspace(path: projectPath)

        let session = ChatSession(id: UUID().uuidString, title: "Server chat", directory: workspace.path)
        appState.upsertSession(session)

        #expect(appState.sidebarSessions(for: workspace).contains { $0.id == session.id })
    }
}
