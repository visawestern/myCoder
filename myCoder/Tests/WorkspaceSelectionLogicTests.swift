import Testing
@testable import myCoder

@Suite("Workspace selection and session loading")
struct WorkspaceSelectionLogicTests {
    @Test("switching workspace requests a session reload")
    func switchingWorkspaceReloadsSessions() {
        #expect(WorkspaceSelectionLogic.shouldReloadSessions(previousID: "project-a", newID: "project-b"))
        #expect(!WorkspaceSelectionLogic.shouldReloadSessions(previousID: "project-a", newID: "project-a"))
    }

    @Test("late session-load results cannot overwrite the selected project")
    func rejectsStaleLoadResult() {
        #expect(WorkspaceSelectionLogic.shouldApplyLoadedSessions(selectedID: "project-b", loadedID: "project-b"))
        #expect(!WorkspaceSelectionLogic.shouldApplyLoadedSessions(selectedID: "project-b", loadedID: "project-a"))
    }

    @Test("nil selection is never treated as a matching project load")
    func rejectsNilSelection() {
        #expect(!WorkspaceSelectionLogic.shouldApplyLoadedSessions(selectedID: nil, loadedID: "project-a"))
    }
}
