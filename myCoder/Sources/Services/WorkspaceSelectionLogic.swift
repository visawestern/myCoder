import Foundation

enum WorkspaceSelectionLogic {
    static func shouldReloadSessions(previousID: String?, newID: String?) -> Bool {
        guard let newID, !newID.isEmpty else { return false }
        return previousID != newID
    }

    static func shouldApplyLoadedSessions(selectedID: String?, loadedID: String) -> Bool {
        guard let selectedID, !selectedID.isEmpty, !loadedID.isEmpty else { return false }
        return selectedID == loadedID
    }
}
