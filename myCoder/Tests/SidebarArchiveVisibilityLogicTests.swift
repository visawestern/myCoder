import Foundation
import Testing
@testable import myCoder

@Suite("SID-05: archived workspace visibility")
struct SidebarArchiveVisibilityLogicTests {
    @Test("archived registry project is excluded from active sidebar")
    func archivedProjectIsHidden() {
        let workspace = Workspace(id: "/tmp/archived", name: "Archived", path: "/tmp/archived", branch: nil, tasks: [])
        let archived = ProjectRegistryEntry(path: "/tmp/archived", name: "Archived", archivedAt: Date())

        #expect(WorkspaceArchiveVisibilityLogic.visible([workspace], registry: [archived]).isEmpty)
    }

    @Test("restore makes the same project visible without recreating its workspace")
    func restoreMakesProjectVisible() {
        let workspace = Workspace(id: "/tmp/project", name: "Project", path: "/tmp/project", branch: nil, tasks: [])
        let archived = ProjectRegistryEntry(path: "/tmp/project", name: "Project", archivedAt: Date())
        let restored = ProjectRegistryLogic.restore(id: archived.id, in: [archived])

        #expect(WorkspaceArchiveVisibilityLogic.visible([workspace], registry: restored) == [workspace])
    }

    @Test("projects absent from the registry remain visible for safe migration")
    func unknownRegistryEntryDoesNotHideWorkspace() {
        let workspace = Workspace(id: "/tmp/unregistered", name: "Unregistered", path: "/tmp/unregistered", branch: nil, tasks: [])

        #expect(WorkspaceArchiveVisibilityLogic.visible([workspace], registry: []).count == 1)
    }
}
