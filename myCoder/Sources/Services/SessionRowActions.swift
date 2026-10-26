import Foundation

/// Pure decisions for session-row actions (click-path audit: every menu item
/// must do what its label promises). A standalone chat has no folder — its
/// "Show in Finder" item must not exist rather than open garbage.
enum SessionRowActions {
    /// Folder to reveal for a session row, or nil when there is nothing
    /// to show (standalone chats live only in the database).
    static func showInFinderURL(session: ChatSession, workspace: Workspace) -> URL? {
        let dir = session.directory.isEmpty ? workspace.path : session.directory
        guard !dir.isEmpty,
              dir != ChatSession.standaloneProjectKey,
              dir.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: dir)
    }
}
