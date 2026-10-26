import Foundation

enum SidebarExpansionLogic {
    /// Clicking the current row toggles; selecting a different row always
    /// expands so the user can immediately see its sessions.
    static func nextState(isAlreadySelected: Bool, isExpanded: Bool) -> Bool {
        isAlreadySelected ? !isExpanded : true
    }

    static func stateAfterSelection(workspaceID: String, selectedID: String?) -> Bool {
        workspaceID == selectedID
    }
}
