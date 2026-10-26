import Foundation

enum ProjectSessionRoutingLogic {
    struct WorkspacePath: Equatable {
        let id: String
        let path: String
    }

    static func path(
        projectID: String,
        selectedPath: String?,
        workspaces: [WorkspacePath]
    ) -> String? {
        if let workspace = workspaces.first(where: { $0.id == projectID }) {
            return workspace.path
        }
        if projectID.hasPrefix("/") {
            return projectID
        }
        return nil
    }
}
