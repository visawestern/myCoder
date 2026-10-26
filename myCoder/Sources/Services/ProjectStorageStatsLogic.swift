import Foundation

enum ProjectStorageStatsLogic {
    /// Identifier of the app-global database (standalone chats without a
    /// project). It is NOT a project: nothing was ever released publicly, so
    /// there is no "legacy project" to keep around (user directive).
    static let globalIdentifier = "__global__"

    struct Snapshot: Equatable {
        let databaseSize: UInt64
        let messageCount: Int
        let active: Int
        let archived: Int
        let projectID: String
    }

    struct SessionCount: Equatable {
        let projectID: String
        let active: Int
        let archived: Int
    }

    struct Aggregate: Equatable {
        let databaseSize: UInt64
        let messageCount: Int
        let snapshotSize: UInt64
        let sessionCounts: [SessionCount]
    }

    static func aggregate(
        global: Snapshot,
        projects: [Snapshot],
        snapshotSize: UInt64
    ) -> Aggregate {
        var unique = [String: Snapshot]()
        for project in projects where project.projectID != global.projectID {
            unique[project.projectID] = project
        }
        let orderedProjects = unique.values.sorted { $0.projectID < $1.projectID }
        let all = [global] + orderedProjects
        return Aggregate(
            databaseSize: all.reduce(0) { $0 + $1.databaseSize },
            messageCount: all.reduce(0) { $0 + $1.messageCount },
            snapshotSize: snapshotSize,
            // Only real projects are listed per project. The global database
            // counts into the totals but never appears as a "Legacy" folder.
            sessionCounts: orderedProjects.map {
                SessionCount(projectID: $0.projectID, active: $0.active, archived: $0.archived)
            }
        )
    }
}
