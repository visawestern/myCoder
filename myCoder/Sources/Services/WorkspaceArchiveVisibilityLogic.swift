import Foundation

/// Reconciles the database-backed workspace list with the lightweight project
/// registry used by Storage and Archive UI. Missing registry rows are treated
/// as active for safe migration; an archived project remains visible only while
/// it is the currently selected workspace, so archiving never destroys context.
enum WorkspaceArchiveVisibilityLogic {
    static func visible(
        _ workspaces: [Workspace],
        registry: [ProjectRegistryEntry],
        selectedPath: String? = nil
    ) -> [Workspace] {
        let archivedPaths = Set(
            registry
                .filter(\.isArchived)
                .map { ChatSession.normalizedPath($0.path) }
        )
        return workspaces.filter { workspace in
            let path = ChatSession.normalizedPath(workspace.path)
            guard archivedPaths.contains(path) else { return true }
            return selectedPath.map { ChatSession.normalizedPath($0) == path } ?? false
        }
    }
}
