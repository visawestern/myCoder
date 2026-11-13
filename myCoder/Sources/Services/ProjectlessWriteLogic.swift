import Foundation

/// Gate for file-changing tools in a chat that has no project folder.
///
/// Input: a tool name and the path the model wants to change.
/// Output: whether the tool needs a project, a suggested project folder name,
/// and the exact refusal text returned to the model.
///
/// Purpose: a project-less chat used to write straight into the home folder
/// (`aquarium_3d.html` landed in `/Users/apple`). The user requirement is to
/// ask for a project in a separate folder before any file change. The gate is
/// pure; the host supplies the UI prompt and the executor enforces the result.
///
/// Dependencies: `WebToolProtocolEmulator` for canonical tool names only.
/// Tested by `ProjectlessWriteLogicTests`.
enum ProjectlessWriteLogic {

    /// Tools that create or change files on disk.
    static func requiresProject(toolName: String) -> Bool {
        let canonical = WebToolProtocolEmulator.canonicalToolName(toolName) ?? toolName
        return canonical == WebEmulatedTool.writeFile.rawValue
            || canonical == WebEmulatedTool.editFile.rawValue
    }

    /// A safe folder name for the new project, derived from the requested file.
    /// `aquarium_3d.html` -> `aquarium_3d`; empty input -> a neutral fallback.
    static func suggestedProjectName(for path: String) -> String {
        let file = (path as NSString).lastPathComponent
        let base = (file as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = base
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "myCoder-project" : cleaned
    }

    /// Result returned to the model instead of executing a write.
    ///
    /// - Parameter createdProjectPath: nil when the user declined; otherwise
    ///   the folder the CURRENT chat was bound to. The turn continues in the
    ///   same chat — the working directory now points into the project, and
    ///   the model must retry the file tool there (директива 2026-11-13).
    static func refusalMessage(createdProjectPath: String?) -> String {
        if let path = createdProjectPath, !path.isEmpty {
            return "ok: this chat is now bound to the project at \(path). "
                + "Working directory changed to the project folder. "
                + "Continue the task — file tools now read and write inside the project. "
                + "Retry the file operation now; do not ask the user to move anything."
        }
        return "error: project_required: this chat has no project folder, so file changes are not allowed. "
            + "The user was asked to create a project. Do not write files; explain that a project is required."
    }
}
