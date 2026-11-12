import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Session Operations
    
    func insertSession(
        id: String,
        projectId: String,
        title: String,
        directory: String,
        branch: String? = nil,
        agentMode: String = "build",
        modelId: String? = nil,
        providerId: String? = nil,
        parentSessionId: String? = nil,
        subagentStatus: String? = nil
    ) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let now = Int64(Date().timeIntervalSince1970)
        do {
            try db.run(sessions.insert(
                sessionId <- id,
                sessionProjectId <- projectId,
                sessionTitle <- title,
                sessionCreatedAt <- now,
                sessionUpdatedAt <- now,
                sessionDirectory <- directory,
                sessionBranch <- branch,
                sessionAgentMode <- agentMode,
                sessionModelId <- modelId,
                sessionProviderId <- providerId,
                sessionParentId <- parentSessionId,
                sessionSubagentStatus <- subagentStatus
            ))
        } catch let Result.error(_, code, _) where code == 19 {
            throw DatabaseError.duplicateEntry
        }
    }

    /// Persist a session's goal (plan Раздел 5 Блок 1 п.10). nil clears it.
    func setSessionGoal(sessionId id: String, goal: String?) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(sessions.filter(sessionId == id).update(sessionGoal <- goal))
    }

    /// Persist the model and provider a standalone chat uses.
    @discardableResult
    func updateSessionModel(sessionId id: String, modelId: String?, providerId: String?) throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.run(sessions.filter(sessionId == id).update(
            sessionModelId <- modelId,
            sessionProviderId <- providerId
        ))
    }

    /// Rename a session in the global (standalone) store.
    /// Rename a session. Returns the number of rows updated so the caller can
    /// detect a stale id instead of reporting success for a silent no-op.
    @discardableResult
    func updateSessionTitle(sessionId id: String, title: String) throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.run(sessions.filter(sessionId == id).update(
            sessionTitle <- title,
            sessionUpdatedAt <- Int64(Date().timeIntervalSince1970)
        ))
    }

    /// True when this store owns the given session id. Used to drop sidebar
    /// rows that survived after their chat was deleted.
    func hasSession(id: String) throws -> Bool {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.pluck(sessions.filter(sessionId == id)) != nil
    }

    /// Каталог сессии по её номеру — нужен откату, чтобы найти проектные
    /// undo-записи и снапшоты даже для чата, который сейчас не выбран.
    func getSessionDirectory(sessionId id: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard let row = try db.pluck(sessions.filter(sessionId == id)) else { return nil }
        return row[sessionDirectory]
    }

    /// Read a session's persisted goal.
    func getSessionGoal(sessionId id: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard let row = try db.pluck(sessions.filter(sessionId == id)) else { return nil }
        return row[sessionGoal]
    }
    
    /// Persist a session's draft text. nil clears it.
    /// Uses INSERT OR REPLACE so a draft can be saved even before the session
    /// has any messages (the session row is created if missing).
    func setSessionDraftText(sessionId id: String, text: String?) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        // If the session row doesn't exist yet, update() is a no-op.
        // Fall back to insert-or-replace so drafts persist for new sessions.
        let existing = try db.pluck(sessions.filter(sessionId == id))
        if existing == nil {
            try db.run(sessions.insert(or: .replace,
                                       sessionId <- id,
                                       sessionProjectId <- "",
                                       sessionTitle <- "New Chat",
                                       sessionCreatedAt <- Int64(Date().timeIntervalSince1970),
                                       sessionUpdatedAt <- Int64(Date().timeIntervalSince1970),
                                       sessionDirectory <- "",
                                       sessionDraftText <- text))
        } else {
            try db.run(sessions.filter(sessionId == id).update(sessionDraftText <- text))
        }
    }
    
    /// Read a session's persisted draft text.
    func getSessionDraftText(sessionId id: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard let row = try db.pluck(sessions.filter(sessionId == id)) else { return nil }
        return row[sessionDraftText]
    }
    
    func getSessionsByProject(projectId: String, includeArchived: Bool = false) throws -> [SessionRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        var query = sessions.filter(sessionProjectId == projectId)
        if !includeArchived {
            query = query.filter(sessionIsArchived == false)
        }
        query = query.order(sessionUpdatedAt.desc)
        
        var results: [SessionRecord] = []
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(query)) {
            results.append(SessionRecord(
                id: row[sessionId],
                projectId: row[sessionProjectId],
                title: row[sessionTitle],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[sessionCreatedAt])),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row[sessionUpdatedAt])),
                directory: row[sessionDirectory],
                branch: row[sessionBranch],
                agentMode: row[sessionAgentMode],
                isArchived: row[sessionIsArchived],
                tokensUsed: Int(row[sessionTokensUsed]),
                costUsd: row[sessionCostUsd],
                draftText: row[sessionDraftText],
                modelId: row[sessionModelId],
                providerId: row[sessionProviderId],
                parentSessionId: row[sessionParentId],
                subagentStatus: row[sessionSubagentStatus]
            ))
        }
        return results
    }
    
    /// Returns every session across every project, regardless of `project_id`.
    func getAllSessionsAcrossProjects() throws -> [SessionRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }

        var results: [SessionRecord] = []
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(sessions.order(sessionUpdatedAt.desc))) {
            results.append(SessionRecord(
                id: row[sessionId],
                projectId: row[sessionProjectId],
                title: row[sessionTitle],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[sessionCreatedAt])),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row[sessionUpdatedAt])),
                directory: row[sessionDirectory],
                branch: row[sessionBranch],
                agentMode: row[sessionAgentMode],
                isArchived: row[sessionIsArchived],
                tokensUsed: Int(row[sessionTokensUsed]),
                costUsd: row[sessionCostUsd],
                draftText: row[sessionDraftText],
                modelId: row[sessionModelId],
                providerId: row[sessionProviderId],
                parentSessionId: row[sessionParentId],
                subagentStatus: row[sessionSubagentStatus]
            ))
        }
        return results
    }

    /// Sub-agent chats spawned by `parentId` inside the global store,
    /// ordered oldest-first so the panel reads like a transcript.
    func childSessions(parentId: String) throws -> [SessionRecord] {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try SQLiteSafeQuery.rows(
            db.prepareRowIterator(sessions.filter(sessionParentId == parentId).order(sessionCreatedAt.asc))
        ).map { row in
            SessionRecord(
                id: row[sessionId],
                projectId: row[sessionProjectId],
                title: row[sessionTitle],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[sessionCreatedAt])),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row[sessionUpdatedAt])),
                directory: row[sessionDirectory],
                branch: row[sessionBranch],
                agentMode: row[sessionAgentMode],
                isArchived: row[sessionIsArchived],
                tokensUsed: Int(row[sessionTokensUsed]),
                costUsd: row[sessionCostUsd],
                draftText: row[sessionDraftText],
                modelId: row[sessionModelId],
                providerId: row[sessionProviderId],
                parentSessionId: row[sessionParentId],
                subagentStatus: row[sessionSubagentStatus]
            )
        }
    }

    /// Persist the chat's plan steps (JSON snapshot of `TaskStep`s).
    ///
    /// Вход: `id` — чат; `stepsJSON` — снимок из
    /// `SessionStepsPersistenceLogic.encode`, nil очищает колонку.
    /// Выход: нет. Зависимости: колонка `sessions.metadata`.
    func setSessionSteps(sessionId id: String, stepsJSON: String?) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(sessions.filter(sessionId == id).update(sessionMetadata <- stepsJSON))
    }

    /// Read the chat's persisted plan steps.
    ///
    /// Вход: `id` — чат. Выход: JSON-снимок или nil.
    /// Зависимости: колонка `sessions.metadata`.
    func getSessionSteps(sessionId id: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }
        return try db.pluck(sessions.filter(sessionId == id).select(sessionMetadata))?[sessionMetadata]
    }

    /// Persist a sub-agent lifecycle status ("running" | "done" | "failed").
    func setSubagentStatus(sessionId id: String, status: String?) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(sessions.filter(sessionId == id).update(sessionSubagentStatus <- status))
    }

    func updateSessionTimestamp(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let session = sessions.filter(sessionId == id)
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(session.update(sessionUpdatedAt <- now))
    }
    
    func archiveSession(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        let session = sessions.filter(sessionId == id)
        try db.run(session.update(sessionIsArchived <- true))
    }
    
    // MARK: - Session Routes
    
    /// Persist the "session id -> owning project path" mapping so the route
    /// survives app restarts (the in-memory map does not).
    func setSessionRoute(sessionId: String, projectPath: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(sessionRoutes.insert(or: .replace,
            sessionRouteSessionId <- sessionId,
            sessionRouteProjectPath <- projectPath,
            sessionRouteUpdatedAt <- now
        ))
    }
    
    /// Stored route for a session, or nil when the session was never routed
    /// to a project database.
    func sessionRoute(sessionId: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }
        guard let row = try db.pluck(sessionRoutes.filter(sessionRouteSessionId == sessionId)) else {
            return nil
        }
        let path: String = row[sessionRouteProjectPath]
        return path.isEmpty ? nil : path
    }

    /// Drop the stored route of a session (the session was deleted or moved
    /// to another project).
    func deleteSessionRoute(sessionId: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        try db.run(sessionRoutes.filter(sessionRouteSessionId == sessionId).delete())
    }
}
