import Foundation

/// User directive 2026-09-08: the app must reopen the project the user last
/// worked in at startup, with its sidebar group expanded (the sidebar already
/// expands the selected project's group, so restoring the selection is
/// enough). Pure resolution for testability.
enum WorkspaceRestoreLogic {
    /// The workspace to reopen: the saved one when it still exists, otherwise
    /// the most recently used existing workspace, otherwise nil (fresh install
    /// / everything deleted — the app starts with no selection, as before).
    static func restore(workspaces: [Workspace], savedID: String?) -> Workspace? {
        if let savedID, !savedID.isEmpty,
           let saved = workspaces.first(where: { $0.id == savedID }) {
            return saved
        }
        return workspaces.first
    }
}
