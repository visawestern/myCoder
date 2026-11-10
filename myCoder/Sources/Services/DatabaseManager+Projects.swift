import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Project Operations
    
    func insertProject(
        id: String,
        name: String,
        path: String,
        gitRemote: String? = nil,
        gitBranch: String? = nil,
        stableId: String? = nil,
        archivedAt: Date? = nil,
        defaultProviderID: String? = nil,
        defaultModelID: String? = nil
    ) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(projects.insert(
            projectId <- id,
            projectName <- name,
            projectPath <- path,
            projectCreatedAt <- now,
            projectLastOpenedAt <- now,
            projectGitRemote <- gitRemote,
            projectGitBranch <- gitBranch,
            projectIsPinned <- false,
            projectStableId <- stableId ?? UUID().uuidString,
            projectArchivedAt <- archivedAt.map { Int64($0.timeIntervalSince1970) },
            projectDefaultProviderId <- defaultProviderID,
            projectDefaultModelId <- defaultModelID
        ))
    }
    
    /// All projects, most-recently-opened first. The default is intentionally
    /// UNLIMITED (E30): the sidebar loads the full project list, and a silent
    /// `LIMIT 100` used to hide every project beyond the 100 most recent with
    /// no indication. Callers that genuinely want a cap pass `limit` explicitly.
    func getAllProjects(limit: Int? = nil) throws -> [ProjectRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        var results: [ProjectRecord] = []
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(projects.order(projectLastOpenedAt.desc).limit(limit))) {
            results.append(projectRecord(from: row))
        }
        return results
    }

    /// Looks up a registry entry by its path-independent `stable_id`. Used
    /// to recognize a project that was moved/renamed on disk: its
    /// `.mycoder/project.db` (which moves with the folder) still reports
    /// the same stable id even though the registry's remembered path is now
    /// stale.
    func findProjectByStableId(_ stableId: String) throws -> ProjectRecord? {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard let row = try db.pluck(projects.filter(projectStableId == stableId)) else { return nil }
        return projectRecord(from: row)
    }

    /// Single SQL row → record mapping shared by every project query so a new
    /// column can never be silently omitted from one of them.
    func projectRecord(from row: Row) -> ProjectRecord {
        ProjectRecord(
            id: row[projectId],
            name: row[projectName],
            path: row[projectPath],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row[projectCreatedAt])),
            lastOpenedAt: Date(timeIntervalSince1970: TimeInterval(row[projectLastOpenedAt])),
            gitRemote: row[projectGitRemote],
            gitBranch: row[projectGitBranch],
            isPinned: row[projectIsPinned],
            stableId: row[projectStableId],
            archivedAt: row[projectArchivedAt].map { Date(timeIntervalSince1970: TimeInterval($0)) },
            defaultProviderID: row[projectDefaultProviderId],
            defaultModelID: row[projectDefaultModelId]
        )
    }

    /// Re-points a registry entry at a new path after the project folder
    /// was moved/renamed outside the app. Since `id` is policy-defined to be
    /// the normalized path (see storage-reset fix), relinking replaces the
    /// row's id as well, while preserving `stableId`/`createdAt` so the
    /// project's identity and history provenance survive the move.
    @discardableResult
    func relinkProject(oldId: String, newPath: String, name: String) throws -> String {
        guard let db = db else { throw DatabaseError.notInitialized }
        let normalizedNewPath = ChatSession.normalizedPath(newPath)
        let existingRow = try db.pluck(projects.filter(projectId == oldId))
        let preservedStableId = existingRow?[projectStableId]
        let createdAt = existingRow?[projectCreatedAt] ?? Int64(Date().timeIntervalSince1970)
        let lastOpenedAt = existingRow?[projectLastOpenedAt] ?? createdAt
        let isPinned = existingRow?[projectIsPinned] ?? false
        // Registry state is a user decision: moving a folder must not unarchive
        // the project or drop its default provider/model.
        let archivedAt = existingRow?[projectArchivedAt]
        let defaultProviderID = existingRow?[projectDefaultProviderId]
        let defaultModelID = existingRow?[projectDefaultModelId]

        try db.transaction {
            try db.run(projects.filter(projectId == oldId).delete())
            try db.run(projects.insert(
                projectId <- normalizedNewPath,
                projectName <- name,
                projectPath <- normalizedNewPath,
                projectCreatedAt <- createdAt,
                projectLastOpenedAt <- lastOpenedAt,
                projectIsPinned <- isPinned,
                projectStableId <- preservedStableId ?? UUID().uuidString,
                projectArchivedAt <- archivedAt,
                projectDefaultProviderId <- defaultProviderID,
                projectDefaultModelId <- defaultModelID
            ))
        }
        return normalizedNewPath
    }

    /// Atomically replace the project registry: rows that are present are
    /// updated, missing ids are inserted, and every row absent from the list
    /// is deleted. Used by the Storage panel for archive/restore/forget and by
    /// configuration import. All statements run in one transaction so a failed
    /// write can never leave a half-renamed registry behind.
    func replaceProjectRegistry(_ records: [ProjectRegistryRecord]) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let now = Int64(Date().timeIntervalSince1970)
        try db.transaction {
            let keep = Set(records.map(\.id))
            let existingIds = try SQLiteSafeQuery
                .rows(db.prepareRowIterator(projects.select(projectId)))
                .map { $0[projectId] }
            for id in existingIds where !keep.contains(id) {
                try db.run(projects.filter(projectId == id).delete())
            }
            for record in records {
                let archived = record.archivedAt.map { Int64($0.timeIntervalSince1970) }
                if try db.pluck(projects.filter(projectId == record.id)) != nil {
                    try db.run(projects.filter(projectId == record.id).update(
                        projectName <- record.name,
                        projectPath <- record.path,
                        projectLastOpenedAt <- Int64(record.lastOpenedAt.timeIntervalSince1970),
                        projectArchivedAt <- archived,
                        projectDefaultProviderId <- record.defaultProviderID,
                        projectDefaultModelId <- record.defaultModelID
                    ))
                } else {
                    try db.run(projects.insert(
                        projectId <- record.id,
                        projectName <- record.name,
                        projectPath <- record.path,
                        projectCreatedAt <- now,
                        projectLastOpenedAt <- Int64(record.lastOpenedAt.timeIntervalSince1970),
                        projectIsPinned <- false,
                        projectStableId <- UUID().uuidString,
                        projectArchivedAt <- archived,
                        projectDefaultProviderId <- record.defaultProviderID,
                        projectDefaultModelId <- record.defaultModelID
                    ))
                }
            }
        }
    }
    
    func updateProjectLastOpened(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let project = projects.filter(projectId == id)
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(project.update(projectLastOpenedAt <- now))
    }
    
    /// Updates mutable fields (name, gitRemote, gitBranch) on an existing project.
    func updateProject(id: String, name: String, gitRemote: String? = nil, gitBranch: String? = nil) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let project = projects.filter(projectId == id)
        var assignments: [Setter] = [projectName <- name]
        if let remote = gitRemote { assignments.append(projectGitRemote <- remote) }
        if let branch = gitBranch { assignments.append(projectGitBranch <- branch) }
        try db.run(project.update(assignments))
    }
    
    func toggleProjectPin(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let project = projects.filter(projectId == id)
        if let row = try db.pluck(project) {
            let currentValue = row[projectIsPinned]
            try db.run(project.update(projectIsPinned <- !currentValue))
        }
    }
}
