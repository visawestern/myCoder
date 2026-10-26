import Testing
import Foundation
@testable import myCoder

/// F71 — the sidebar is one tree: every project is a row with its chats as
/// children, and every chat without a project is its own top-level row. No
/// chat may appear twice, and pinned rows float to the top.
@Suite("Sidebar tree (F71)")
struct SidebarTreeBuilderTests {

    private func workspace(_ id: String, name: String = "Project") -> Workspace {
        Workspace(id: id, name: name, path: "/tmp/\(id)", tasks: [])
    }

    private func session(
        _ id: String,
        updatedAt: Date = Date(),
        directory: String = "/tmp/p1"
    ) -> ChatSession {
        ChatSession(id: id, title: "Chat \(id)", updatedAt: updatedAt, directory: directory)
    }

    @Test func projectChatsAreChildrenOfTheirProject() {
        let p1 = workspace("p1")
        let items = SidebarTreeBuilder.build(
            workspaces: [p1],
            sessionsByWorkspaceID: ["p1": [
                session("s1", updatedAt: Date(timeIntervalSince1970: 200)),
                session("s2", updatedAt: Date(timeIntervalSince1970: 100))
            ]],
            projectlessSessions: []
        )

        #expect(items.count == 1)
        guard case .project(let node) = items[0] else {
            Issue.record("expected a project row")
            return
        }
        #expect(node.id == "p1")
        #expect(node.sessions.map(\.id) == ["s1", "s2"])
    }

    @Test func projectlessChatBecomesItsOwnTopLevelRow() {
        let items = SidebarTreeBuilder.build(
            workspaces: [workspace("p1")],
            sessionsByWorkspaceID: ["p1": []],
            projectlessSessions: [session("free", directory: ChatSession.standaloneProjectKey)]
        )

        #expect(items.count == 2)
        guard case .projectlessChat(let node) = items[1] else {
            Issue.record("expected a project-less chat row")
            return
        }
        #expect(node.id == "free")
        #expect(node.session.directory == ChatSession.standaloneProjectKey)
    }

    @Test func aChatBelongingToAProjectNeverAppearsTwice() {
        let shared = session("s1", directory: "/tmp/p1")
        let items = SidebarTreeBuilder.build(
            workspaces: [workspace("p1")],
            sessionsByWorkspaceID: ["p1": [shared]],
            projectlessSessions: [shared]
        )

        #expect(items.count == 1)
        guard case .project(let node) = items[0] else {
            Issue.record("expected only the project row")
            return
        }
        #expect(node.sessions.map(\.id) == ["s1"])
    }

    @Test func childrenAreSortedByRecentActivity() {
        let older = session("old", updatedAt: Date(timeIntervalSince1970: 100))
        let newer = session("new", updatedAt: Date(timeIntervalSince1970: 200))
        let items = SidebarTreeBuilder.build(
            workspaces: [workspace("p1")],
            sessionsByWorkspaceID: ["p1": [older, newer]],
            projectlessSessions: []
        )

        guard case .project(let node) = items[0] else {
            Issue.record("expected a project row")
            return
        }
        #expect(node.sessions.map(\.id) == ["new", "old"])
    }

    @Test func pinnedRowsFloatToTheTopAndKeepRelativeOrder() {
        let items = SidebarTreeBuilder.build(
            workspaces: [workspace("p1"), workspace("p2"), workspace("p3")],
            sessionsByWorkspaceID: [:],
            projectlessSessions: [],
            pinnedIDs: [SidebarPinID.project("p3"), SidebarPinID.project("p1")]
        )

        // Pinned rows keep their relative order (p1 before p3) and float above
        // the unpinned project.
        #expect(items.map(\.id) == ["project-p1", "project-p3", "project-p2"])
    }

    @Test func projectAndChatPinsUseSeparateNamespaces() {
        let items = SidebarTreeBuilder.build(
            workspaces: [workspace("shared")],
            sessionsByWorkspaceID: [:],
            projectlessSessions: [session("shared", directory: ChatSession.standaloneProjectKey)],
            pinnedIDs: [SidebarPinID.chat("shared")]
        )

        #expect(items.count == 2)
        #expect(items.first?.id == "chat-shared")
        #expect(items.last?.id == "project-shared")
    }

    @Test func pinStoreRoundTripsThroughDefaults() {
        let suite = "SidebarTreeBuilderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let ids: Set<String> = [SidebarPinID.project("p1"), SidebarPinID.chat("c1")]
        SidebarPinStore.save(ids, defaults: defaults)
        #expect(SidebarPinStore.load(defaults: defaults) == ids)
    }
}
