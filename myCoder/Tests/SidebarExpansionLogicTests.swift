import Foundation
import Testing
@testable import myCoder

@MainActor
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

    @Test("Выбор проекта раскрывает его, но не схлопывает остальные")
    func selectionChangeState() {
        // Новый проект раскрывается, даже если был свёрнут.
        #expect(SidebarExpansionLogic.stateAfterSelection(
            workspaceID: "b", selectedID: "b", isExpanded: false))
        // Раскрытый ранее проект остаётся раскрытым.
        #expect(SidebarExpansionLogic.stateAfterSelection(
            workspaceID: "a", selectedID: "b", isExpanded: true))
        // Свёрнутый ранее проект не раскрывается принудительно.
        #expect(!SidebarExpansionLogic.stateAfterSelection(
            workspaceID: "a", selectedID: "b", isExpanded: false))
    }
}
