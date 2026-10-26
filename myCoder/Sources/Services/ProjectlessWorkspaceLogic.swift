import Foundation

/// The "no project" mode: a chat that is not attached to a project folder.
///
/// Such a chat still needs a real working directory — otherwise every tool
/// call resolves relative paths against a non-existent folder and shell
/// commands run from an arbitrary place. The home folder is used instead: the
/// chat can work with files, and anything outside the chat's own folder is
/// handled by the out-of-project access request.
enum ProjectlessWorkspaceLogic {
    static var workspaceID: String { ChatSession.standaloneProjectKey }

    /// Working directory of a project-less chat.
    static func workingDirectory(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        homeDirectory
    }

    /// True when the given workspace is the synthetic project-less workspace.
    static func isProjectless(_ workspace: Workspace?) -> Bool {
        workspace?.id == workspaceID
    }

    /// Working directory of the open chat.
    ///
    /// A project chat uses its project folder. A project-less chat uses the
    /// home folder even while a project is selected in the sidebar — the open
    /// chat decides, not the sidebar selection.
    static func workingDirectory(
        sessionDirectory: String?,
        workspacePath: String?,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        if let sessionDirectory, !sessionDirectory.isEmpty {
            return sessionDirectory == workspaceID ? homeDirectory : sessionDirectory
        }
        if let workspacePath, !workspacePath.isEmpty, workspacePath != workspaceID {
            return workspacePath
        }
        return homeDirectory
    }
}
