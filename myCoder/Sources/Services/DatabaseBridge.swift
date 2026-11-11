import Foundation
import Combine

/// Bridge-слой для интеграции DatabaseManager с существующим AppState
/// Автоматическая синхронизация между памятью и БД
class DatabaseBridge: ObservableObject {
    static let shared = DatabaseBridge()
    
    let db = DatabaseManager.shared
    private let keychain = KeychainManager.shared
    
    private var cancellables = Set<AnyCancellable>()

    /// Resolves `candidatePath` to its per-project database, or `nil` if the
    /// path doesn't point to a real, existing project directory.
    ///
    /// Chats no longer live here (user directive 2026-10-29: "они должны у нас
    /// быть все в базе данных программы а не храниться в папке с проектом").
    /// Only project metadata that is not chat content — spec wizard drafts —
    /// still uses the project file.
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
    func clearSpecWizardDraft(projectPath: String) -> Bool {
        guard let projectDB = resolveProjectDatabase(for: projectPath) else { return false }
        do {
            try projectDB.setMetadataValue("", forKey: "spec_wizard_draft")
            return true
        } catch {
            print("❌ Failed to clear spec wizard draft: \(error)")
            return false
        }
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
    
    /// Chats of a project, read from the program database (`~/.mycoder/
    /// mycoder.db`) only. The project folder is never a chat store and is
    /// never read for chats (user directive 2026-10-29: chats must live only
    /// in the program database).
    func loadSessions(projectId: String) -> [ChatSession] {
        let normalizedProjectPath = ChatSession.normalizedPath(projectId)
        guard !normalizedProjectPath.isEmpty else { return [] }
        do {
            let records = try db.getSessionsByProject(
                projectId: normalizedProjectPath,
                includeArchived: false
            )
            return records.filter { $0.parentSessionId == nil }.map { record in
                ChatSession(
                    id: record.id,
                    title: record.title,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    directory: record.directory,
                    branch: record.branch,
                    gitSummary: nil,
                    sessionGoal: (try? db.getSessionGoal(sessionId: record.id)) ?? nil,
                    modelID: record.modelId,
                    providerID: record.providerId,
                    parentSessionID: record.parentSessionId,
                    subagentStatus: record.subagentStatus
                )
            }
        } catch {
            print("❌ Failed to load sessions from the program database: \(error)")
            return []
        }
    }

    /// Каталог чата по номеру сессии. Нужен откату: чат может быть не
    /// выбран в интерфейсе, поэтому проект нельзя брать из сайдбара.
    func sessionDirectory(forSessionID sessionID: String) -> String? {
        try? db.getSessionDirectory(sessionId: sessionID)
    }

    /// Create a sub-agent chat owned by `parentID` in the program database.
    /// The child is marked "running" and is excluded from the sidebar by the
    /// parent filter — it surfaces in the right panel instead.
    func createSubagentSession(
        parentSessionID: String,
        projectKey: String,
        directory: String,
        title: String
    ) -> ChatSession {
        let isStandalone = projectKey == ChatSession.standaloneProjectKey
        let child = ChatSession(
            title: title,
            directory: isStandalone ? ChatSession.standaloneProjectKey : directory,
            parentSessionID: parentSessionID,
            subagentStatus: SubagentRunner.statusRunning
        )
        do {
            try db.insertSession(
                id: child.id,
                projectId: isStandalone ? ChatSession.standaloneProjectKey : ChatSession.normalizedPath(projectKey),
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

    /// Lifecycle status update for a sub-agent chat.
    func setSubagentStatus(sessionID: String, status: String?) {
        try? db.setSubagentStatus(sessionId: sessionID, status: status)
    }

    /// Sub-agent chats of `parentID` from the program database.
    func loadChildSessions(parentID: String, projectKey: String) -> [ChatSession] {
        let records = (try? db.childSessions(parentId: parentID)) ?? []
        return records.map { record in
            ChatSession(
                id: record.id,
                title: record.title,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                directory: record.directory,
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
    
    /// Create a new chat row in the program database (upsert semantics: an
    /// existing id keeps its row and only the mutable metadata is refreshed).
    /// Project chats are keyed by the normalized project path, standalone
    /// chats by the reserved `standalone` key. No project folder is written.
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
        let isStandalone = projectId == ChatSession.standaloneProjectKey
        let owner = isStandalone
            ? ChatSession.standaloneProjectKey
            : ChatSession.normalizedPath(projectId)
        do {
            try db.insertSession(
                id: id,
                projectId: owner,
                title: title,
                directory: directory,
                branch: branch,
                agentMode: agentMode,
                modelId: modelId,
                providerId: providerId
            )
        } catch DatabaseError.duplicateEntry {
            // Already present: keep the row, refresh the metadata the caller
            // passed. `createSession` is called again when a remote session is
            // mirrored locally, so duplicate must stay a no-op instead of an
            // error.
            _ = try? db.updateSessionTitle(sessionId: id, title: title)
            _ = try? db.updateSessionModel(sessionId: id, modelId: modelId, providerId: providerId)
        } catch {
            print("❌ Failed to create session: \(error)")
        }
    }
    
    /// Persist a session goal in the program database.
    func setSessionGoal(sessionId id: String, goal: String?) {
        do {
            try db.setSessionGoal(sessionId: id, goal: goal)
        } catch {
            print("❌ Failed to persist session goal: \(error)")
        }
    }

    /// Persist the model and provider a chat uses.
    /// Returns true only when a row actually changed.
    @discardableResult
    func setSessionModel(sessionId id: String, modelID: String?, providerID: String?) -> Bool {
        do {
            return try db.updateSessionModel(sessionId: id, modelId: modelID, providerId: providerID) > 0
        } catch {
            print("❌ Failed to persist session model: \(error)")
            return false
        }
    }

    /// Rename a session in the program database.
    /// Returns true only when a row actually changed.
    @discardableResult
    func renameSession(id: String, title: String) -> Bool {
        do {
            return try db.updateSessionTitle(sessionId: id, title: title) > 0
        } catch {
            print("❌ Failed to rename session: \(error)")
            return false
        }
    }

    /// True when the program database still holds this session. Sidebar rows
    /// use it to detect a chat that was deleted outside the UI instead of
    /// opening a permanently empty chat.
    func sessionExists(id: String) -> Bool {
        (try? db.hasSession(id: id)) ?? false
    }

    /// Hard-delete a session (messages cascade) from the program database.
    @discardableResult
    func deleteSession(id: String) -> Bool {
        do {
            return try db.deleteSession(id: id)
        } catch {
            print("❌ Failed to delete session: \(error)")
            return false
        }
    }

    /// Archive a session in the program database.
    @discardableResult
    func archiveSession(id: String) -> Bool {
        do {
            try db.archiveSession(id: id)
            return true
        } catch {
            print("❌ Failed to archive session: \(error)")
            return false
        }
    }
    
    // MARK: - Message Persistence

    /// Both `DatabaseManager` and `ProjectDatabaseManager` expose an
    /// `insertMessagePart` with the same shape; this closure lets
    /// `saveMessagePart` write to whichever one is active without
    /// duplicating the per-part-type switch for each backend.
    typealias MessagePartInserter = (
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

    /// Сохранить сообщение в базе данных программы.
    func saveMessage(_ message: Message, sessionId: String) {
        MyCoderAPIServer.appendLog("💾 saveMessage: id=\(message.id), session=\(sessionId)")
        do {
            try db.insertMessage(
                id: message.id,
                sessionId: sessionId,
                role: roleToString(message.role),
                content: message.content,
                reasoning: message.reasoning.isEmpty ? nil : message.reasoning,
                usage: message.usage,
                metadata: MessageMetadataCodec.encode(
                    sendInfo: message.sendInfo,
                    contextSummary: message.contextSummary
                )
            )
            // Persist every part (text, reasoning, tool_call, steps, images).
            // Stale rows are cleared first: a message is re-saved on every
            // update and a removed part must not linger next to the fresh set.
            try db.deleteMessageParts(messageId: message.id)
            for (index, part) in message.parts.enumerated() {
                try saveMessagePart(part, messageId: message.id, sequenceOrder: index, insert: db.insertMessagePart)
            }
            MyCoderAPIServer.appendLog("💾 saveMessage: insertMessage + \(message.parts.count) parts succeeded")
        } catch {
            MyCoderAPIServer.appendLog("❌ Failed to save message: \(error)")
        }
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
    
    func roleToString(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }
    
    func stringToRole(_ string: String) -> MessageRole {
        switch string {
        case "user": return .user
        case "assistant": return .assistant
        case "system": return .system
        default: return .user
        }
    }

    static func decodeSendInfo(_ json: String?) -> MessageSendInfo? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MessageSendInfo.self, from: data)
    }

    static func encodeSendInfo(_ info: MessageSendInfo?) -> String? {
        guard let info, let data = try? JSONEncoder().encode(info) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
