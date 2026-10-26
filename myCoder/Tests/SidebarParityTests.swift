import Testing
import Foundation
@testable import myCoder

@Suite("Sidebar Workspace Logic")
struct SidebarWorkspaceLogicTests {

    @Test("Filters workspaces by name")
    func filterByName() {
        let workspaces = [
            Workspace(id: "1", name: "tm3", path: "/a/tm3"),
            Workspace(id: "2", name: "ZCodeProject", path: "/a/zcode")
        ]
        let filtered = SidebarWorkspaceLogic.filtered(workspaces, query: "tm")
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "tm3")
    }

    @Test("Empty query returns all workspaces")
    func emptyQuery() {
        let workspaces = [
            Workspace(id: "1", name: "tm3", path: "/a/tm3"),
            Workspace(id: "2", name: "ZCodeProject", path: "/a/zcode")
        ]
        #expect(SidebarWorkspaceLogic.filtered(workspaces, query: "").count == 2)
    }

    @Test("Sorts workspaces by name ascending")
    func sortNameAsc() {
        let workspaces = [
            Workspace(id: "1", name: "zcode", path: "/a/z"),
            Workspace(id: "2", name: "tm3", path: "/a/t")
        ]
        let sorted = SidebarWorkspaceLogic.sorted(workspaces, order: .nameAsc, sessions: [])
        #expect(sorted.map(\.name) == ["tm3", "zcode"])
    }

    @Test("Sorts workspaces by task count")
    func sortTaskCount() {
        let workspaces = [
            Workspace(id: "1", name: "few", path: "/a/f"),
            Workspace(id: "2", name: "many", path: "/a/m")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "A", directory: "/a/m"),
            ChatSession(id: "s2", title: "B", directory: "/a/m"),
            ChatSession(id: "s3", title: "C", directory: "/a/f")
        ]
        let sorted = SidebarWorkspaceLogic.sorted(workspaces, order: .taskCount, sessions: sessions)
        #expect(sorted.first?.name == "many")
    }

    @Test("User initials from display name")
    func userInitials() {
        #expect(UserProfileDisplay.initials(from: "Win Pei") == "WP")
        #expect(UserProfileDisplay.initials(from: "MiMo") == "MI")
    }

    @Test("Sidebar action icons match plan")
    func sidebarActionIcons() {
        #expect(SidebarLayout.newTaskIcon == "plus.circle")
        #expect(SidebarLayout.workspacesExpandIcon == "arrow.up.forward.square")
        #expect(SidebarLayout.workspacesFilterIcon == "line.3.horizontal.decrease")
        #expect(SidebarLayout.workspacesSearchIcon == "magnifyingglass")
        #expect(SidebarLayout.workspacesViewListIcon == "list.bullet")
        #expect(SidebarLayout.workspacesViewGridIcon == "square.grid.2x2")
    }
    
    // MARK: - Session Count Filtering
    
    @Test("Filter preset 'all' returns all workspaces")
    func filterPresetAll() {
        let workspaces = [
            Workspace(id: "1", name: "Full", path: "/a/full"),
            Workspace(id: "2", name: "Empty", path: "/a/empty")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task", directory: "/a/full")
        ]
        let result = SidebarWorkspaceLogic.filteredBySessionCount(workspaces, sessions: sessions, preset: .all)
        #expect(result.count == 2)
    }
    
    @Test("Filter preset 'has sessions' excludes empty workspaces")
    func filterPresetHasSessions() {
        let workspaces = [
            Workspace(id: "1", name: "Full", path: "/a/full"),
            Workspace(id: "2", name: "Empty", path: "/a/empty")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task", directory: "/a/full")
        ]
        let result = SidebarWorkspaceLogic.filteredBySessionCount(workspaces, sessions: sessions, preset: .hasSessions)
        #expect(result.count == 1)
        #expect(result[0].name == "Full")
    }
    
    @Test("Filter preset 'empty' returns only empty workspaces")
    func filterPresetEmpty() {
        let workspaces = [
            Workspace(id: "1", name: "Full", path: "/a/full"),
            Workspace(id: "2", name: "Empty", path: "/a/empty")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task", directory: "/a/full")
        ]
        let result = SidebarWorkspaceLogic.filteredBySessionCount(workspaces, sessions: sessions, preset: .empty)
        #expect(result.count == 1)
        #expect(result[0].name == "Empty")
    }
    
    @Test("Filter preset 'has sessions' returns all when all workspaces have sessions")
    func filterPresetHasSessionsAll() {
        let workspaces = [
            Workspace(id: "1", name: "A", path: "/a"),
            Workspace(id: "2", name: "B", path: "/b")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task 1", directory: "/a"),
            ChatSession(id: "s2", title: "Task 2", directory: "/b")
        ]
        let result = SidebarWorkspaceLogic.filteredBySessionCount(workspaces, sessions: sessions, preset: .hasSessions)
        #expect(result.count == 2)
    }
    
    @Test("Filter preset 'has sessions' returns none when no workspaces have sessions")
    func filterPresetHasSessionsNone() {
        let workspaces = [Workspace(id: "1", name: "Empty", path: "/a/empty")]
        let result = SidebarWorkspaceLogic.filteredBySessionCount(workspaces, sessions: [], preset: .hasSessions)
        #expect(result.isEmpty)
    }
    
    @Test("Sort by name descending works correctly")
    func sortNameDesc() {
        let workspaces = [
            Workspace(id: "1", name: "alpha", path: "/a"),
            Workspace(id: "2", name: "beta", path: "/b"),
            Workspace(id: "3", name: "gamma", path: "/c")
        ]
        let sorted = SidebarWorkspaceLogic.sorted(workspaces, order: .nameDesc, sessions: [])
        #expect(sorted.map(\.name) == ["gamma", "beta", "alpha"])
    }
    
    @Test("Sort by recent use with mixed dates")
    func sortRecentUse() {
        let workspaces = [
            Workspace(id: "1", name: "Old", path: "/a/old"),
            Workspace(id: "2", name: "New", path: "/a/new")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Old task", updatedAt: Date(timeIntervalSince1970: 1000), directory: "/a/old"),
            ChatSession(id: "s2", title: "New task", updatedAt: Date(timeIntervalSince1970: 2000), directory: "/a/new")
        ]
        let sorted = SidebarWorkspaceLogic.sorted(workspaces, order: .recentUse, sessions: sessions)
        #expect(sorted.first?.name == "New")
    }
    
    @Test("Sort by recent use uses distantPast for workspaces without sessions")
    func sortRecentUseEmptyWorkspace() {
        let workspaces = [
            Workspace(id: "1", name: "Has session", path: "/a/has"),
            Workspace(id: "2", name: "No session", path: "/a/none")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task", updatedAt: Date(timeIntervalSince1970: 1000), directory: "/a/has")
        ]
        let sorted = SidebarWorkspaceLogic.sorted(workspaces, order: .recentUse, sessions: sessions)
        #expect(sorted.first?.name == "Has session")
        #expect(sorted.last?.name == "No session")
    }
    
    @Test("Session count returns zero for workspace without sessions")
    func sessionCountZero() {
        let workspace = Workspace(id: "1", name: "Empty", path: "/empty")
        let count = SidebarWorkspaceLogic.sessionCount(for: workspace, sessions: [])
        #expect(count == 0)
    }
    
    @Test("Filter is case-insensitive")
    func filterCaseInsensitive() {
        let workspaces = [
            Workspace(id: "1", name: "MyProject", path: "/a/mp"),
            Workspace(id: "2", name: "OtherProject", path: "/a/op")
        ]
        let result = SidebarWorkspaceLogic.filtered(workspaces, query: "myproject")
        #expect(result.count == 1)
        #expect(result[0].name == "MyProject")
    }
    
    @Test("Filter query ignores leading/trailing whitespace")
    func filterTrimsWhitespace() {
        let workspaces = [
            Workspace(id: "1", name: "MyProject", path: "/a/mp")
        ]
        let result = SidebarWorkspaceLogic.filtered(workspaces, query: "  MyProject  ")
        #expect(result.count == 1)
    }
    
    @Test("Filtering by name then by session count works in combination")
    func combinedFilterAndSessionFilter() {
        let workspaces = [
            Workspace(id: "1", name: "Alpha Project", path: "/a/ap"),
            Workspace(id: "2", name: "Alpha Empty", path: "/a/ae"),
            Workspace(id: "3", name: "Beta Legacy", path: "/a/bl")
        ]
        let sessions = [
            ChatSession(id: "s1", title: "Task", directory: "/a/ap")
        ]
        
        // Step 1: filter by name
        let nameFiltered = SidebarWorkspaceLogic.filtered(workspaces, query: "Alpha")
        #expect(nameFiltered.count == 2)
        
        // Step 2: filter by session count
        let result = SidebarWorkspaceLogic.filteredBySessionCount(nameFiltered, sessions: sessions, preset: .hasSessions)
        #expect(result.count == 1)
        #expect(result[0].name == "Alpha Project")
    }
}
