import Foundation

/// Decides what a send targets when the caller did not name a chat.
///
/// `/api/send` used to always create a standalone chat, so an open project was
/// ignored: the chat's directory became the home folder, the system prompt said
/// `cwd: /Users/apple`, and the model — handed a context pack full of project
/// files — answered "the project is not in the current directory" and searched
/// the whole disk (live run 2026-11-03). The target follows the open project.
struct SendTargetPlan: Equatable {
    let createsStandalone: Bool
    let workspacePath: String
    let workingDirectory: String
    let reusesChatId: String?
}

enum SendTargetPlanLogic {

    static func plan(chatId: String?,
                     selectedWorkspace: Workspace?,
                     homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> SendTargetPlan {
        let existing = (chatId?.isEmpty == false) ? chatId : nil
        let workspacePath = selectedWorkspace?.path ?? ChatSession.standaloneProjectKey
        let isProjectless = selectedWorkspace == nil
            || workspacePath == ChatSession.standaloneProjectKey
        return SendTargetPlan(
            createsStandalone: existing == nil && isProjectless,
            workspacePath: workspacePath,
            workingDirectory: isProjectless ? homeDirectory : workspacePath,
            reusesChatId: existing
        )
    }
}
