import Foundation

/// Which project's context a turn must collect.
///
/// A chat owns its project (`ChatSession.directory`). The context collection
/// used the globally selected workspace, so a chat opened for project A could
/// collect (and send to the model) files, rules and plans of project B —
/// live check 2026-11-08: a myCoder chat received llama.cpp context. The
/// session's root wins; the workspace is only the fallback for chats that
/// have no project yet (brand-new sessions, standalone chats).
enum SessionProjectRootLogic {

    static func resolve(sessionDirectory: String?, selectedWorkspacePath: String?) -> String {
        if let sessionDirectory {
            let trimmed = sessionDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != ChatSession.standaloneProjectKey {
                return trimmed
            }
        }
        return selectedWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
