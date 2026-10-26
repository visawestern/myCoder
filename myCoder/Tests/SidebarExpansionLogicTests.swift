import Foundation
import Testing
@testable import myCoder

@Suite("SID-06: workspace selection expansion")
struct SidebarExpansionLogicTests {
    @Test("selecting another workspace expands its section")
    func selectingAnotherWorkspaceExpands() {
        #expect(SidebarExpansionLogic.nextState(isAlreadySelected: false, isExpanded: false))
        #expect(SidebarExpansionLogic.nextState(isAlreadySelected: false, isExpanded: true))
    }

    @Test("clicking the current workspace toggles its section")
    func currentWorkspaceToggles() {
        #expect(SidebarExpansionLogic.nextState(isAlreadySelected: true, isExpanded: false))
        #expect(!SidebarExpansionLogic.nextState(isAlreadySelected: true, isExpanded: true))
    }

    @Test("selection change makes exactly the selected section active")
    func selectionChangeState() {
        #expect(SidebarExpansionLogic.stateAfterSelection(workspaceID: "b", selectedID: "b"))
        #expect(!SidebarExpansionLogic.stateAfterSelection(workspaceID: "a", selectedID: "b"))
    }
}
