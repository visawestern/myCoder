import Foundation

/// Handling of a tool call whose path lies outside the project folder.
///
/// The host must not dead-end such a call with a bare validation error: the
/// user is asked for access to that folder, and an approved grant lets the
/// call run. The model never decides on its own that a path is off-limits —
/// it emits the tool call and the host decides.
enum OutOfProjectAccessLogic {
    /// Folder that covers the requested path: the path itself when it is a
    /// directory, its parent folder otherwise.
    static func grantRoot(
        forPath path: String,
        fileManager: FileManager = .default
    ) -> String {
        let absolute = path.hasPrefix("/")
            ? path
            : FileManager.default.currentDirectoryPath + "/" + path
        let standardized = (absolute as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory), isDirectory.boolValue {
            return standardized
        }
        return (standardized as NSString).deletingLastPathComponent
    }

    /// True when the path lies inside the project folder or inside one of the
    /// folders the user granted access to.
    static func isAccessible(
        path: String,
        projectRoot: String,
        grantedRoots: [String] = [],
        fileManager: FileManager = .default
    ) -> Bool {
        if WebToolProtocolEmulator.isPathInsideRoot(path, root: projectRoot) {
            return true
        }
        guard path.hasPrefix("/") else { return false }
        return grantedRoots.contains { WebToolProtocolEmulator.isPathInsideRoot(path, root: $0) }
    }

    /// Approval card shown to the user.
    static func approvalMessage(tool: String, path: String, projectRoot: String) -> String {
        "The agent asked to use \(tool) on \(path), which is outside the project folder \(projectRoot). Allow access to that folder?"
    }

    /// Result fed back to the model when the user refuses the access.
    static func denialMessage(tool: String, path: String) -> String {
        "the user denied access to \(path) (outside the project folder), so \(tool) was not executed. Do not retry the same path; ask the user how to proceed."
    }

    /// Result fed back to the model when the path is still out of reach after
    /// the grant (for example a path the grant does not cover).
    static func validationMessage(path: String) -> String {
        "validation error: pathEscapesProject(\(path)) — the folder is outside the project and the user did not grant access to it."
    }
}
