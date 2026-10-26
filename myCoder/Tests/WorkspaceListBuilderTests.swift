import Testing
import Foundation
@testable import myCoder

@Suite("Workspace List Builder")
struct WorkspaceListBuilderTests {

    @Test("Builds workspaces only from sessions with tasks")
    func buildsFromSessions() {
        let sessions = [
            ChatSession(id: "s1", title: "Task A", directory: "/Users/test/tm3"),
            ChatSession(id: "s2", title: "Task B", directory: "/Users/test/tm3"),
            ChatSession(id: "s3", title: "Task C", directory: "/Users/test/ZCodeProject")
        ]
        let workspaces = WorkspaceListBuilder.build(from: sessions, projectWorktree: "/Users/test/mimo-macos")

        #expect(workspaces.count == 2)
        #expect(workspaces.contains { $0.name == "tm3" })
        #expect(workspaces.contains { $0.name == "ZCodeProject" })
    }

    @Test("Does not inject empty project worktree workspace")
    func noEmptyRootWorkspace() {
        let sessions = [
            ChatSession(id: "s1", title: "Task A", directory: "/Users/test/tm3")
        ]
        let workspaces = WorkspaceListBuilder.build(
            from: sessions,
            projectWorktree: "/Users/test/mimo-macos"
        )
        #expect(!workspaces.contains { $0.name == "mimo-macos" })
        #expect(workspaces.count == 1)
    }

    @Test("Sorts workspaces by most recent session")
    func sortedByRecent() {
        let old = Date().addingTimeInterval(-86400 * 3)
        let recent = Date()
        let sessions = [
            ChatSession(id: "s1", title: "Old", updatedAt: old, directory: "/a/old"),
            ChatSession(id: "s2", title: "New", updatedAt: recent, directory: "/a/new")
        ]
        let workspaces = WorkspaceListBuilder.build(from: sessions, projectWorktree: nil)
        #expect(workspaces.first?.name == "new")
    }

    @Test("Session task icon matches reference")
    func sessionTaskIcon() {
        #expect(SidebarLayout.sessionTaskIcon == "bubble.left")
    }
}
