import Foundation

enum ProjectHeaderContextLogic {
    static func shouldShowBranch(selectedWorkspace: Bool, selectedLegacyProject: Bool) -> Bool {
        selectedWorkspace || selectedLegacyProject
    }
}
