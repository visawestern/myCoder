import Foundation
import Combine

/// Bridge-слой для интеграции DatabaseManager с существующим AppState
/// Автоматическая синхронизация между памятью и БД
class DatabaseBridge: ObservableObject {
    static let shared = DatabaseBridge()
    
    private let db = DatabaseManager.shared
    private let keychain = KeychainManager.shared
    
    private var cancellables = Set<AnyCancellable>()

    /// Session/message routing is keyed by session id. This prevents one
    /// selected workspace from changing the storage destination of another
    /// session while requests are in flight.
    private let activeProjectLock = NSLock()
    private var sessionProjectPaths: [String: String] = [:]
    /// Sessions that are known NOT to belong to any project (standalone chats
    /// and legacy local sessions). Negative cache so the discovery scan does
    /// not run again for every message of such a session.
    private var sessionsWithoutProject: Set<String> = []

    private func projectPath(forSessionID sessionID: String) -> String? {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        return sessionProjectPaths[sessionID]
    }

    private func rememberProject(_ path: String, forSessionID sessionID: String) {
        activeProjectLock.lock()
        sessionProjectPaths[sessionID] = path
        sessionsWithoutProject.remove(sessionID)
        activeProjectLock.unlock()
    }

    private func markSessionWithoutProject(_ sessionID: String) {
        activeProjectLock.lock()
        sessionsWithoutProject.insert(sessionID)
        activeProjectLock.unlock()
    }

    private func isKnownWithoutProject(_ sessionID: String) -> Bool {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        return sessionsWithoutProject.contains(sessionID)
    }

    /// Bind `sessionID` to `path` so project-scoped session/message routing
    /// resolves for flows that never call `loadSessions(projectId:)` (e.g. a
    /// chat opened straight from a recent-chats or grid view). Idempotent.
    func registerSessionProject(sessionID: String, projectPath path: String) {
        let normalized = ChatSession.normalizedPath(path)
        guard !normalized.isEmpty else { return }
        rememberProject(normalized, forSessionID: sessionID)
        persistRoute(sessionID: sessionID, projectPath: normalized)
    }

    /// Same as `registerSessionProject`, but only for paths that are
    /// registered projects. A session's `directory` may point anywhere (a
    /// subdirectory, a removed folder), and routing it to a non-project path
    /// would create a bogus project database.
    func registerSessionProjectIfKnown(sessionID: String, projectPath path: String) {
        let normalized = ChatSession.normalizedPath(path)
        guard normalized.hasPrefix("/"), normalized != ChatSession.standaloneProjectKey else { return }
        let known = ((try? db.getAllProjects()) ?? []).contains {
            ChatSession.normalizedPath($0.path) == normalized
        }
        guard known else { return }
        registerSessionProject(sessionID: sessionID, projectPath: normalized)
    }

    private func persistRoute(sessionID: String, projectPath path: String) {
        do {
            try db.setSessionRoute(sessionId: sessionID, projectPath: path)
        } catch {
            print("❌ Failed to persist session route: \(sessionID)")
        }
    }

    /// Drop the routing of a session (the session was deleted or moved to a
    /// different project).
    func forgetSessionProject(sessionID: String) {
        activeProjectLock.lock()
        sessionProjectPaths.removeValue(forKey: sessionID)
        activeProjectLock.unlock()
        try? db.deleteSessionRoute(sessionId: sessionID)
    }

    /// Resolves the project database that owns `sessionID`.
    ///
    /// The in-memory map is rebuilt on every launch, so it cannot be the only
    /// source of truth: a session opened without its project's sidebar (recent
    /// chats, grid view) used to resolve to nothing and its history was read
    /// from — and written to — the global database instead of the project one.
    /// Resolution order: in-memory map → durable route row → discovery across
    /// registered projects (self-heals sessions created before routes were
    /// persisted).
    private func resolveProjectDatabase(forSessionID sessionID: String) -> ProjectDatabaseManager? {
        if let path = projectPath(forSessionID: sessionID),
           let projectDB = resolveProjectDatabase(for: path) {
            return projectDB
        }
        if let path = (try? db.sessionRoute(sessionId: sessionID)) ?? nil,
           let projectDB = resolveProjectDatabase(for: path) {
            rememberProject(path, forSessionID: sessionID)
            return projectDB
        }
        if isKnownWithoutProject(sessionID) { return nil }
        if let path = discoverProjectPath(forSessionID: sessionID),
           let projectDB = resolveProjectDatabase(for: path) {
            rememberProject(path, forSessionID: sessionID)
            persistRoute(sessionID: sessionID, projectPath: path)
            return projectDB
        }
        markSessionWithoutProject(sessionID)
        return nil
    }

    /// Finds the registered project that owns `sessionID` by asking each
    /// project's database directly. Only projects that already have a database
    /// file are inspected — discovery must not create stores as a side effect.
    private func discoverProjectPath(forSessionID sessionID: String) -> String? {
        let projects = (try? db.getAllProjects()) ?? []
        for project in projects {
            let path = ChatSession.normalizedPath(project.path)
            guard path.hasPrefix("/") else { continue }
            guard ProjectDatabaseManager.hasExistingDatabase(projectPath: path) else { continue }
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path) else { continue }
            if (try? projectDB.hasSession(id: sessionID)) == true {
                return path
            }
        }
        return nil
    }

    /// Resolves `candidatePath` to its per-project database, or `nil` if the
    /// path doesn't point to a real, existing project directory.
    private func resolveProjectDatabase(for candidatePath: String) -> ProjectDatabaseManager? {
        guard !candidatePath.isEmpty else { return nil }
        return try? ProjectDatabaseManager.manager(forProjectPath: candidatePath)
    }

    // MARK: - Spec wizard draft

    func loadSpecWizardDraft(projectPath: String) -> SpecWizardDraft? {
        guard let projectDB = resolveProjectDatabase(for: projectPath),
              let raw = try? projectDB.metadataValue(forKey: "spec_wizard_draft"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SpecWizardDraft.self, from: data)
    }

    @discardableResult
    func saveSpecWizardDraft(_ draft: SpecWizardDraft, projectPath: String) -> Bool {
        guard let projectDB = resolveProjectDatabase(for: projectPath) else { return false }
        var stored = draft
        stored.updatedAt = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(stored),
              let raw = String(data: data, encoding: .utf8) else { return false }
        do {
            try projectDB.setMetadataValue(raw, forKey: "spec_wizard_draft")
            return true
        } catch {
            print("❌ Failed to save spec wizard draft: \(error)")
            return false
        }
    }

    // MARK: - Project Management
    
    /// Загрузить все проекты из БД
    func loadProjects() -> [Workspace] {
        do {
            let records = try db.getAllProjects()
            return records.map { record in
                Workspace(
                    id: record.id,
                    name: record.name,
                    path: record.path,
                    branch: record.gitBranch,
                    tasks: [] // Lazy load: sessions → tasks conversion happens in AppState
                )
            }
        } catch {
            print("❌ Failed to load projects: \(error)")
            return []
        }
    }
    
    /// Создать или обновить проект в БД
    func upsertProject(id: String, name: String, path: String, gitRemote: String? = nil, gitBranch: String? = nil) {
        do {
            // Проверяем существование
            let existing = try? db.getAllProjects().first(where: { $0.id == id })
            
            if let existing {
                // Update mutable fields on existing records (name, branch, remote)
                // instead of silently ignoring changes.
                try db.updateProject(
                    id: id,
                    name: name,
                    gitRemote: gitRemote ?? existing.gitRemote,
                    gitBranch: gitBranch ?? existing.gitBranch
                )
                try db.updateProjectLastOpened(id: id)
            } else {
                try db.insertProject(
                    id: id,
                    name: name,
                    path: path,
                    gitRemote: gitRemote,
                    gitBranch: gitBranch
                )
            }
        } catch {
            print("❌ Failed to upsert project: \(error)")
        }
    }
    
    /// Пометить проект как недавно открытый
    func markProjectAsOpened(id: String) {
        do {
            try db.updateProjectLastOpened(id: id)
        } catch {
            print("❌ Failed to mark project as opened: \(error)")
        }
    }
    
    /// Toggle pin статус проекта
    func toggleProjectPin(id: String) {
        do {
            try db.toggleProjectPin(id: id)
        } catch {
            print("❌ Failed to toggle pin: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    /// Загрузить сессии проекта. Резолвит `projectId` в его собственную
    /// per-project БД (см. `ProjectDatabaseManager`). Проект обязан быть
    /// существующей директорией; невалидные идентификаторы не записываются.
    func loadSessions(projectId: String) -> [ChatSession] {
        if let projectDB = resolveProjectDatabase(for: projectId) {
            do {
                let records = try projectDB.getAllSessions(includeArchived: false)
                return records.filter { $0.parentSessionId == nil }.map { record in
                    let normalizedProjectPath = ChatSession.normalizedPath(projectId)
                    rememberProject(normalizedProjectPath, forSessionID: record.id)
                    persistRoute(sessionID: record.id, projectPath: normalizedProjectPath)
                    return ChatSession(
                        id: record.id,
                        title: record.title,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt,
                        directory: record.directory,
                        branch: record.branch,
                        gitSummary: nil,
                        sessionGoal: record.sessionGoal,
                        modelID: record.modelId,
                        providerID: record.providerId,
                        parentSessionID: record.parentSessionId,
                        subagentStatus: record.subagentStatus
                    )
                }
            } catch {
                print("❌ Failed to load sessions from project database: \(error)")
                return []
            }
        }
        return []
    }

    /// Create a sub-agent chat owned by `parentID` in the same store the
    /// parent uses (per-project database, or the global store for standalone
    /// chats). The child is marked "running" and is excluded from the sidebar
    /// by the parent filter — it surfaces in the right panel instead.
    func createSubagentSession(
        parentSessionID: String,
        projectKey: String,
        directory: String,
        title: String
    ) -> ChatSession {
        let child = ChatSession(
            title: title,
            directory: projectKey == ChatSession.standaloneProjectKey ? ChatSession.standaloneProjectKey : directory,
            parentSessionID: parentSessionID,
            subagentStatus: SubagentRunner.statusRunning
        )
        if projectKey == ChatSession.standaloneProjectKey {
            do {
                try db.insertSession(
                    id: child.id,
                    projectId: ChatSession.standaloneProjectKey,
                    title: child.title,
                    directory: child.directory,
                    parentSessionId: parentSessionID,
                    subagentStatus: SubagentRunner.statusRunning
                )
            } catch {
                print("❌ Failed to create sub-agent session: \(error)")
            }
            return child
        }
        guard let projectDB = resolveProjectDatabase(for: projectKey) else {
            print("❌ Cannot create sub-agent session without a project database: \(projectKey)")
            return child
        }
        let normalizedProjectPath = ChatSession.normalizedPath(projectKey)
        rememberProject(normalizedProjectPath, forSessionID: child.id)
        persistRoute(sessionID: child.id, projectPath: normalizedProjectPath)
        do {
            try projectDB.insertSession(
                id: child.id,
                title: child.title,
                directory: directory,
                parentSessionId: parentSessionID,
                subagentStatus: SubagentRunner.statusRunning
            )
        } catch {
            print("❌ Failed to create sub-agent session in project database: \(error)")
        }
        return child
    }

    /// Lifecycle status update routed to the store that owns `sessionID`.
    func setSubagentStatus(sessionID: String, status: String?) {
        if let projectDB = resolveProjectDatabase(forSessionID: sessionID) {
            try? projectDB.setSubagentStatus(id: sessionID, status: status)
            return
        }
        try? db.setSubagentStatus(sessionId: sessionID, status: status)
    }

    /// Sub-agent chats of `parentID`, loaded from the parent's own store.
    func loadChildSessions(parentID: String, projectKey: String) -> [ChatSession] {
        if projectKey == ChatSession.standaloneProjectKey {
            let records = (try? db.childSessions(parentId: parentID)) ?? []
            return records.map { record in
                ChatSession(
                    id: record.id,
                    title: record.title,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    directory: ChatSession.standaloneProjectKey,
                    branch: record.branch,
                    gitSummary: nil,
                    sessionGoal: nil,
                    modelID: record.modelId,
                    providerID: record.providerId,
                    parentSessionID: record.parentSessionId,
                    subagentStatus: record.subagentStatus
                )
            }
        }
        guard let projectDB = resolveProjectDatabase(for: projectKey) else { return [] }
        let records = (try? projectDB.childSessions(parentId: parentID)) ?? []
        let normalizedProjectPath = ChatSession.normalizedPath(projectKey)
        return records.map { record in
            rememberProject(normalizedProjectPath, forSessionID: record.id)
            persistRoute(sessionID: record.id, projectPath: normalizedProjectPath)
            return ChatSession(
                id: record.id,
                title: record.title,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                directory: record.directory,
                branch: record.branch,
                gitSummary: nil,
                sessionGoal: record.sessionGoal,
                modelID: record.modelId,
                providerID: record.providerId,
                parentSessionID: record.parentSessionId,
                subagentStatus: record.subagentStatus
            )
        }
    }

    /// Load persisted standalone chats (no workspace) from the global
    /// database (audit 2026-09-08). Messages for these sessions already
    /// route through the global store (`isTemporarySession`), so loading the
    /// session rows is enough to restore them across restarts.
    func loadStandaloneSessions() -> [ChatSession] {
        let records = (try? db.getAllSessionsAcrossProjects()) ?? []
        return records
            .filter { $0.projectId == ChatSession.standaloneProjectKey && !$0.isArchived && $0.parentSessionId == nil }
            .map { record in
                ChatSession(
                    id: record.id,
                    title: record.title,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    directory: ChatSession.standaloneProjectKey,
                    branch: record.branch,
                    gitSummary: nil,
                    sessionGoal: nil,
                    modelID: record.modelId,
                    providerID: record.providerId,
                    parentSessionID: record.parentSessionId,
                    subagentStatus: record.subagentStatus
                )
            }
    }
    
    /// Создать новую сессию (upsert — обновляет если существует). Пишет в
    /// per-project БД, резолвленную по `projectId`. Сессия без существующего
    /// project path отклоняется, чтобы история не попадала в другой store.
    func createSession(
        id: String,
        projectId: String,
        title: String,
        directory: String,
        branch: String? = nil,
        agentMode: String = "build",
        modelId: String? = nil,
        providerId: String? = nil
    ) {
        // Audit 2026-09-08: standalone chats (no workspace) persist in the
        // GLOBAL database under the reserved `standalone` project key, so
        // they survive restarts and stay visible in the sidebar's Chats group.
        if projectId == ChatSession.standaloneProjectKey {
            do {
                try db.insertSession(
                    id: id,
                    projectId: ChatSession.standaloneProjectKey,
                    title: title,
                    directory: directory,
                    branch: branch,
                    agentMode: agentMode,
                    modelId: modelId,
                    providerId: providerId
                )
            } catch {
                print("❌ Failed to create standalone session: \(error)")
            }
            return
        }

        // A project may legitimately live under the OS temporary directory
        // (tests, scratch workspaces, and disposable clones). Use the global
        // database only when the directory is temporary AND projectId is not a
        // valid project root; a real project root always owns its per-project DB.
        let tempDir = FileManager.default.temporaryDirectory.path
        let isEphemeralSession = directory.hasPrefix(tempDir)
            && resolveProjectDatabase(for: projectId) == nil
        if isEphemeralSession {
            do {
                try db.insertSession(
                    id: id,
                    projectId: directory,
                    title: title,
                    directory: directory,
                    branch: branch,
                    agentMode: agentMode,
                    modelId: modelId,
                    providerId: providerId
                )
            } catch {
                print("❌ Failed to create temporary session: \(error)")
            }
            return
        }
        
        guard let projectDB = resolveProjectDatabase(for: projectId) else {
            print("❌ Cannot create session without a valid project directory: \(projectId)")
            return
        }
        rememberProject(ChatSession.normalizedPath(projectId), forSessionID: id)
        persistRoute(sessionID: id, projectPath: ChatSession.normalizedPath(projectId))
        do {
            try projectDB.insertSession(
                id: id,
                title: title,
                directory: directory,
                branch: branch,
                agentMode: agentMode,
                modelId: modelId,
                providerId: providerId
            )
        } catch {
            print("❌ Failed to create session in project database: \(error)")
        }
    }
    
    /// Persist a session goal in the same project-scoped store used for reload.
    /// Legacy/temporary sessions retain the global DatabaseManager fallback.
    func setSessionGoal(sessionId id: String, goal: String?) {
        if let projectDB = resolveProjectDatabase(forSessionID: id) {
            do {
                try projectDB.setSessionGoal(id: id, goal: goal)
            } catch {
                print("❌ Failed to persist project session goal: \(error)")
            }
            return
        }
        do {
            try db.setSessionGoal(sessionId: id, goal: goal)
        } catch {
            print("❌ Failed to persist legacy session goal: \(error)")
        }
    }

    /// Persist the model and provider a chat uses in the store that owns it.
    /// Returns true only when a row actually changed.
    @discardableResult
    func setSessionModel(sessionId id: String, modelID: String?, providerID: String?) -> Bool {
        if let projectDB = resolveProjectDatabase(forSessionID: id) {
            do {
                return try projectDB.updateSessionModel(id: id, modelId: modelID, providerId: providerID) > 0
            } catch {
                print("❌ Failed to persist project session model: \(error)")
                return false
            }
        }
        do {
            return try db.updateSessionModel(sessionId: id, modelId: modelID, providerId: providerID) > 0
        } catch {
            print("❌ Failed to persist legacy session model: \(error)")
            return false
        }
    }

    /// Rename a session in the store that owns it (project DB or global).
    /// Returns true only when a row actually changed.
    @discardableResult
    func renameSession(id: String, title: String) -> Bool {
        if let projectDB = resolveProjectDatabase(forSessionID: id) {
            do {
                return try projectDB.updateSessionTitle(id: id, title: title) > 0
            } catch {
                print("❌ Failed to rename project session: \(error)")
                return false
            }
        }
        do {
            return try db.updateSessionTitle(sessionId: id, title: title) > 0
        } catch {
            print("❌ Failed to rename legacy session: \(error)")
            return false
        }
    }

    /// Hard-delete a session (messages cascade) from the store that owns it.
    @discardableResult
    func deleteSession(id: String) -> Bool {
        if let projectDB = resolveProjectDatabase(forSessionID: id) {
            do {
                return try projectDB.deleteSession(id: id)
            } catch {
                print("❌ Failed to delete project session: \(error)")
                return false
            }
        }
        do {
            return try db.deleteSession(id: id)
        } catch {
            print("❌ Failed to delete legacy session: \(error)")
            return false
        }
    }

    /// Архивировать сессию в базе проекта, которому она принадлежит.
    func archiveSession(id: String) {
        guard let projectDB = resolveProjectDatabase(forSessionID: id) else {
            print("❌ Cannot archive session without a registered project: \(id)")
            return
        }
        do {
            try projectDB.archiveSession(id: id)
        } catch {
            print("❌ Failed to archive session in project database: \(error)")
        }
    }
    
    // MARK: - Message Persistence

    /// Both `DatabaseManager` and `ProjectDatabaseManager` expose an
    /// `insertMessagePart` with the same shape; this closure lets
    /// `saveMessagePart` write to whichever one is active without
    /// duplicating the per-part-type switch for each backend.
    private typealias MessagePartInserter = (
        _ id: String,
        _ messageId: String,
        _ type: String,
        _ content: String?,
        _ toolName: String?,
        _ toolArgs: String?,
        _ toolResult: String?,
        _ toolCallId: String?,
        _ sequenceOrder: Int
    ) throws -> Void

    /// Сохранить сообщение в базе проекта, которому принадлежит сессия.
    func saveMessage(_ message: Message, sessionId: String) {
        MyCoderAPIServer.appendLog("💾 saveMessage: id=\(message.id), session=\(sessionId), temp=\(isTemporarySession(sessionId))")
        // For temporary sessions, use global database
        if isTemporarySession(sessionId) {
            MyCoderAPIServer.appendLog("💾 saveMessage: using global db for temp session")
            do {
                try db.insertMessage(
                    id: message.id,
                    sessionId: sessionId,
                    role: roleToString(message.role),
                    content: message.content,
                    reasoning: message.reasoning.isEmpty ? nil : message.reasoning,
                    usage: message.usage
                )
                // Persist every part (text, reasoning, tool_call, steps, images)
                // exactly like project sessions, so temp sessions reload with
                // their tool calls intact instead of losing them. Stale rows
                // are cleared first: a message is re-saved on every update and
                // a removed part must not linger next to the fresh set.
                try db.deleteMessageParts(messageId: message.id)
                for (index, part) in message.parts.enumerated() {
                    try saveMessagePart(part, messageId: message.id, sequenceOrder: index, insert: db.insertMessagePart)
                }
                MyCoderAPIServer.appendLog("💾 saveMessage: insertMessage + \(message.parts.count) parts succeeded")
            } catch {
                MyCoderAPIServer.appendLog("❌ Failed to save temporary message: \(error)")
            }
            return
        }
        
        guard let projectDB = resolveProjectDatabase(forSessionID: sessionId) else {
            print("❌ Cannot save message without a registered project: \(sessionId)")
            return
        }
        do {
            try projectDB.insertMessage(
                id: message.id,
                sessionId: sessionId,
                role: roleToString(message.role),
                content: message.content,
                reasoning: message.reasoning.isEmpty ? nil : message.reasoning,
                usage: message.usage
            )
            // Stale rows are cleared first (see the temp-session branch above).
            try projectDB.deleteMessageParts(messageId: message.id)
            for (index, part) in message.parts.enumerated() {
                try saveMessagePart(part, messageId: message.id, sequenceOrder: index, insert: projectDB.insertMessagePart)
            }
        } catch {
            print("❌ Failed to save message in project database: \(error)")
        }
    }
    
    private func isTemporarySession(_ sessionId: String) -> Bool {
        if let path = projectPath(forSessionID: sessionId) {
            // A real project can live under /tmp. The registered project
            // database, not the filesystem prefix, is the source of truth for
            // routing.
            return resolveProjectDatabase(for: path) == nil
        }
        // A project session can ALSO have a row in the global sessions table
        // (sessions created before the project was resolved are written there
        // first). That row must not win over the project store — otherwise the
        // history is read from the global database, which holds none of it,
        // and the chat comes up empty. So the project stores are asked first.
        if resolveProjectDatabase(forSessionID: sessionId) != nil { return false }
        return true
    }
    
    /// Сохранить часть сообщения через переданный project database inserter.
    private func saveMessagePart(
        _ part: MessagePartContent,
        messageId: String,
        sequenceOrder: Int,
        insert: MessagePartInserter
    ) throws {
        // Stable part id: a tool call keeps its callID so repeated saves of
        // the same part REPLACE the row instead of stacking duplicates (an
        // update per streaming poll used to multiply parts ×N). Other part
        // types derive a deterministic id from their content.
        let partId: String
        switch part {
        case .toolCall(_, _, _, let callId):
            partId = callId ?? "\(messageId)-tool-\(sequenceOrder)"
        case .routeInfo:
            partId = "\(messageId)-route-\(sequenceOrder)"
        case .text(let text):
            partId = "\(messageId)-text-\(text.hashValue)-\(sequenceOrder)"
        case .reasoning(let text):
            partId = "\(messageId)-reasoning-\(text.hashValue)-\(sequenceOrder)"
        case .stepStart:
            partId = "\(messageId)-step-start-\(sequenceOrder)"
        case .stepFinish:
            partId = "\(messageId)-step-finish-\(sequenceOrder)"
        case .image(let base64, _):
            partId = "\(messageId)-image-\(base64.hashValue)-\(sequenceOrder)"
        }

        switch part {
        case .text(let text):
            try insert(partId, messageId, "text", text, nil, nil, nil, nil, sequenceOrder)

        case .reasoning(let text):
            try insert(partId, messageId, "reasoning", text, nil, nil, nil, nil, sequenceOrder)

        case .toolCall(let name, let args, let result, let callId):
            try insert(partId, messageId, "tool_call", nil, name, args, result, callId, sequenceOrder)

        case .stepStart:
            try insert(partId, messageId, "step_start", nil, nil, nil, nil, nil, sequenceOrder)

        case .stepFinish:
            try insert(partId, messageId, "step_finish", nil, nil, nil, nil, nil, sequenceOrder)

        case .image(let base64, let mimeType):
            try insert(partId, messageId, "image", "\(mimeType)|\(base64)", nil, nil, nil, nil, sequenceOrder)

        case .routeInfo(let chips):
            let data = (try? JSONSerialization.data(withJSONObject: chips, options: []))
                ?? Data("[]".utf8)
            try insert(partId, messageId, "route_info",
                       String(data: data, encoding: .utf8) ?? "[]",
                       nil, nil, nil, nil, sequenceOrder)
        }
    }
    
    /// Messages of a session that still live in the GLOBAL database although
    /// the session belongs to a project. That split happened while the route
    /// of the session was unknown (the in-memory route map is per-launch), so
    /// the newest part of such a conversation was written to the global store
    /// and never showed up in the project store.
    ///
    /// The recovery moves those rows into the owning project database and
    /// returns them, so the conversation reads as one stream again.
    @discardableResult
    func recoverGlobalMessages(sessionId: String) -> [Message] {
        guard let projectDB = resolveProjectDatabase(forSessionID: sessionId) else { return [] }
        let records = (try? db.getMessagesBySession(sessionId: sessionId, limit: nil, offset: 0)) ?? []
        guard !records.isEmpty else { return [] }

        var recovered: [Message] = []
        for record in records {
            let parts = (try? db.getMessageParts(messageId: record.id)) ?? []
            let usage = UsageCapture(
                promptTokens: record.promptTokens ?? 0,
                completionTokens: record.completionTokens ?? 0,
                costUSD: record.costUsd,
                modelID: record.modelId ?? "",
                providerID: record.providerId ?? ""
            )
            let hasUsage = record.promptTokens != nil || record.completionTokens != nil
            do {
                try projectDB.insertMessage(
                    id: record.id,
                    sessionId: sessionId,
                    role: record.role,
                    content: record.content,
                    modelId: record.modelId,
                    providerId: record.providerId,
                    reasoning: record.reasoning,
                    isFinished: record.isFinished,
                    usage: hasUsage ? usage : nil,
                    createdAt: record.createdAt
                )
                try projectDB.deleteMessageParts(messageId: record.id)
                for (index, part) in parts.enumerated() {
                    try saveMessagePart(
                        convertPartRecord(part),
                        messageId: record.id,
                        sequenceOrder: index,
                        insert: projectDB.insertMessagePart
                    )
                }
                // The project store owns the row now — drop the global copy so
                // the next load does not see the same message twice.
                try db.deleteMessage(id: record.id)
                recovered.append(Message(
                    id: record.id,
                    role: stringToRole(record.role),
                    content: record.content,
                    parts: parts.map { convertPartRecord($0) },
                    reasoning: record.reasoning ?? "",
                    isFinished: record.isFinished
                ))
            } catch {
                print("❌ Failed to recover global message \(record.id) into project database")
            }
        }
        return recovered
    }

    /// Загрузить сообщения только из базы проекта, зарегистрированной для сессии.
    /// `offset` отсчитывается от начала (ASC). Для начальной загрузки истории
    /// используйте `loadMessageTail` — oldest-first + limit прячет новые
    /// сообщения, как только сессия перерастает размер страницы.
    func loadMessages(sessionId: String, limit: Int? = nil, offset: Int = 0) -> [Message] {
        // For temporary sessions, use global database
        if isTemporarySession(sessionId) {
            do {
                let records = try db.getMessagesBySession(sessionId: sessionId, limit: limit, offset: offset)
                return records.map { record in
                    let parts = (try? db.getMessageParts(messageId: record.id)) ?? []
                    return Message(
                        id: record.id,
                        role: stringToRole(record.role),
                        content: record.content,
                        isStreaming: false,
                        parts: parts.map { convertPartRecord($0) },
                        reasoning: record.reasoning ?? "",
                        isFinished: record.isFinished
                    )
                }
            } catch {
                print("❌ Failed to load temporary messages: \(error)")
                return []
            }
        }
        
        guard let projectDB = resolveProjectDatabase(forSessionID: sessionId) else {
            print("❌ Cannot load messages without a registered project: \(sessionId)")
            return []
        }
        do {
            let records = try projectDB.getMessages(sessionId: sessionId, limit: limit, offset: offset)
            return records.map { record in
                let parts = (try? projectDB.getMessageParts(messageId: record.id)) ?? []
                return Message(
                    id: record.id,
                    role: stringToRole(record.role),
                    content: record.content,
                    isStreaming: false,
                    parts: parts.map { convertProjectPartRecord($0) },
                    reasoning: record.reasoning ?? "",
                    isFinished: record.isFinished
                )
            }
        } catch {
            print("❌ Failed to load messages from project database: \(error)")
            return []
        }
    }

    /// Total persisted messages of a session in its routed store.
    func messageCount(sessionId: String) -> Int {
        if isTemporarySession(sessionId) {
            return (try? db.countMessages(sessionId: sessionId)) ?? 0
        }
        guard let projectDB = resolveProjectDatabase(forSessionID: sessionId) else { return 0 }
        return (try? projectDB.countMessages(sessionId: sessionId)) ?? 0
    }

    /// User messages with visible text in the whole session — the unit the
    /// chat navigator numbers, independent of the loaded history page.
    func userMessageCount(sessionId: String) -> Int {
        if isTemporarySession(sessionId) {
            return (try? db.countUserMessages(sessionId: sessionId)) ?? 0
        }
        guard let projectDB = resolveProjectDatabase(forSessionID: sessionId) else { return 0 }
        return (try? projectDB.countUserMessages(sessionId: sessionId)) ?? 0
    }

    /// Newest `take` messages in ASC display order (`nil` = all). The initial
    /// history load MUST use the tail: oldest-first + limit hides every new
    /// message once a session grows past the page size, and nothing can page
    /// to them afterwards.
    func loadMessageTail(sessionId: String, take: Int?) -> [Message] {
        guard let take else { return loadMessages(sessionId: sessionId, limit: nil) }
        let total = messageCount(sessionId: sessionId)
        let bounded = min(max(take, 0), total)
        guard bounded > 0 else { return [] }
        return loadMessages(sessionId: sessionId, limit: bounded, offset: total - bounded)
    }

    /// One older page preceding the currently displayed tail. `loadedCount` is
    /// how many messages are already shown. Returns the page (ASC) plus whether
    /// even older rows remain.
    func loadOlderPage(sessionId: String, loadedCount: Int, pageSize: Int) -> (messages: [Message], hasMore: Bool) {
        let total = messageCount(sessionId: sessionId)
        let olderCount = total - max(loadedCount, 0)
        guard olderCount > 0, pageSize > 0 else { return ([], false) }
        let take = min(pageSize, olderCount)
        let offset = olderCount - take
        let page = loadMessages(sessionId: sessionId, limit: take, offset: offset)
        return (page, offset > 0)
    }
    
    /// Shared conversion for every part-record shape (global + per-project
    /// DBs use identical column sets). Audit ARCH-09: the two previous
    /// converters were byte-identical — one canonical implementation now
    /// serves both call sites.
    private func convertPartFields(type: String,
                                   content: String?,
                                   toolName: String?,
                                   toolArgs: String?,
                                   toolResult: String?,
                                   toolCallId: String?) -> MessagePartContent {
        switch type {
        case "text":
            return .text(content ?? "")
        case "reasoning":
            return .reasoning(content ?? "")
        case "tool_call":
            return .toolCall(
                name: toolName ?? "",
                args: toolArgs ?? "{}",
                result: toolResult,
                callID: toolCallId
            )
        case "step_start":
            return .stepStart
        case "step_finish":
            return .stepFinish
        case "image":
            if let content {
                let parts = content.split(separator: "|", maxSplits: 1)
                let mimeType = parts.count > 0 ? String(parts[0]) : "image/png"
                let base64 = parts.count > 1 ? String(parts[1]) : ""
                return .image(base64: base64, mimeType: mimeType)
            }
            return .text("")
        case "route_info":
            if let content,
               let data = content.data(using: .utf8),
               let chips = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return .routeInfo(chips: chips)
            }
            return .routeInfo(chips: [])
        default:
            return .text("")
        }
    }

    /// Конвертировать MessagePartRecord (общая БД) в MessagePartContent
    private func convertPartRecord(_ record: MessagePartRecord) -> MessagePartContent {
        convertPartFields(type: record.type,
                          content: record.content,
                          toolName: record.toolName,
                          toolArgs: record.toolArgs,
                          toolResult: record.toolResult,
                          toolCallId: record.toolCallId)
    }

    /// Конвертировать ProjectMessagePartRecord (per-project БД) в MessagePartContent
    private func convertProjectPartRecord(_ record: ProjectMessagePartRecord) -> MessagePartContent {
        convertPartFields(type: record.type,
                          content: record.content,
                          toolName: record.toolName,
                          toolArgs: record.toolArgs,
                          toolResult: record.toolResult,
                          toolCallId: record.toolCallId)
    }
    
    // MARK: - Provider & API Key Management
    
    /// Миграция провайдеров в БД + API keys в Keychain
    func migrateProvidersToSecureStorage(providers: [CustomProvider]) {
        for provider in providers {
            // Save API key to Keychain
            let apiKey = provider.apiKey
            if !apiKey.isEmpty {
                do {
                    try keychain.saveAPIKey(apiKey, for: provider.id)
                    print("✅ Migrated API key for provider: \(provider.id)")
                } catch {
                    print("❌ Failed to migrate API key for \(provider.id): \(error)")
                }
            }
            
            // Save provider metadata to DB (future implementation)
            // Provider table insert here
        }
    }
    
    /// Получить API key провайдера из Keychain
    func getProviderAPIKey(providerId: String) -> String? {
        guard keychain.hasAPIKey(for: providerId) else { return nil }
        do {
            return try keychain.getAPIKey(for: providerId)
        } catch {
            print("⚠️ Failed to read API key for provider \(providerId): \(error)")
            return nil
        }
    }
    
    /// Проверить наличие API key
    func hasProviderAPIKey(providerId: String) -> Bool {
        keychain.hasAPIKey(for: providerId)
    }
    
    /// Сохранить новый API key
    func saveProviderAPIKey(providerId: String, apiKey: String) {
        do {
            try keychain.saveAPIKey(apiKey, for: providerId)
        } catch {
            print("❌ Failed to save API key: \(error)")
        }
    }
    
    /// Удалить API key провайдера
    func deleteProviderAPIKey(providerId: String) {
        do {
            try keychain.deleteAPIKey(for: providerId)
        } catch {
            print("❌ Failed to delete API key: \(error)")
        }
    }
    
    // MARK: - Full-Text Search
    
    /// Поиск сообщений через FTS5
    func searchMessages(query: String) -> [String] {
        do {
            return try db.searchMessages(query: query, limit: 50)
        } catch {
            print("❌ Search failed: \(error)")
            return []
        }
    }
    
    // MARK: - Maintenance
    
    /// Выполнить maintenance если нужно (vacuum раз в неделю)
    func performMaintenanceIfNeeded() {
        db.performMaintenanceIfNeeded()
    }
    
    // MARK: - Helper Methods
    
    private func roleToString(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }
    
    private func stringToRole(_ string: String) -> MessageRole {
        switch string {
        case "user": return .user
        case "assistant": return .assistant
        case "system": return .system
        default: return .user
        }
    }
}
