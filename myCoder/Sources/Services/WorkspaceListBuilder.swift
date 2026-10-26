import Foundation

enum WorkspaceListBuilder {

    static func build(from sessions: [ChatSession], projectWorktree: String?) -> [Workspace] {
        _ = projectWorktree
        let eligible = sessions.filter { session in
            let path = ChatSession.normalizedPath(session.directory)
            guard !path.isEmpty else { return false }
            return true
        }

        let grouped = Dictionary(grouping: eligible) { ChatSession.normalizedPath($0.directory) }

        let workspaces: [Workspace] = grouped.map { path, groupedSessions in
            let sortedSessions = groupedSessions.sorted { $0.updatedAt > $1.updatedAt }
            let name = (path as NSString).lastPathComponent
            return Workspace(
                id: path,
                name: name,
                path: path,
                branch: sortedSessions.first?.branch,
                tasks: sortedSessions.map {
                    WorkspaceTask(id: $0.id, title: $0.title, duration: $0.durationLabel)
                }
            )
        }

        return workspaces.sorted { lhs, rhs in
            latestDate(in: lhs, sessions: eligible) > latestDate(in: rhs, sessions: eligible)
        }
    }

    private static func latestDate(in workspace: Workspace, sessions: [ChatSession]) -> Date {
        sessions
            .filter { $0.belongs(to: workspace) }
            .map(\.updatedAt)
            .max() ?? .distantPast
    }
}
