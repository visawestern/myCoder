// DatabaseManager integration extension for AppState
import Foundation
import AppKit
import UniformTypeIdentifiers

extension AppState {
    
    /// Получить доступ к DatabaseBridge
    var db: DatabaseBridge {
        DatabaseBridge.shared
    }
    
    /// Инициализация базы данных
    @MainActor
    func initializeDatabase() async {
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: start")
        // 0. Projects live in the database. A legacy `projects.json` from an
        //    older build is imported once (only into an empty `projects`
        //    table) and archived, so no side registry survives.
        ProjectRegistryStore.importLegacyJSON(homeDirectory: registryHomeDirectory)
        // 1. Выполнить maintenance + авто-архивация
        DatabaseManager.shared.performMaintenanceIfNeeded()
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: maintenance kicked off")

        // 2. Загрузить проекты из БД
        await loadProjectsFromDatabase()
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: projects loaded")

        // 3. Загрузить стандалон-чаты (аудит 2026-09-08: раньше пропадали)
        loadStandaloneSessionsIntoState()
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: standalone merged, sessions=\(sessions.count)")

        // 4. Восстановить последний проект (user directive 2026-09-08) —
        //    селекция тянет за собой загрузку его сессий, а сайдбар
        //    раскрывает группу выбранного проекта автоматически.
        restoreLastWorkspace()
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: workspace restored")

        // 5. Если есть выбранный проект, загрузить его сессии
        if let currentProjectId = selectedWorkspace?.id {
            await loadSessionsFromDatabase(projectId: currentProjectId)
        }
        MyCoderAPIServer.appendLog("🧭 initializeDatabase: done, sessions=\(sessions.count)")

        print("✅ Database initialized successfully")
    }
    
    /// Загрузить проекты из локальной БД
    @MainActor
    func loadProjectsFromDatabase() async {
        let projects = db.loadProjects()
        
        // Convert to Workspace format (tasks will be populated from sessions)
        let workspacesList = projects.map { project in
            Workspace(
                id: project.id,
                name: project.name,
                path: project.path,
                branch: project.branch,
                tasks: [] // Will be populated from sessions
            )
        }
        
        self.workspaces = workspacesList
        self.refreshProjectRegistry()
        
        print("✅ Loaded \(projects.count) projects from database")
    }
    
    /// Загрузить сессии проекта из БД
    @MainActor
    func loadSessionsFromDatabase(projectId: String) async {
        // The synthetic "Chats" group (and any unknown id) has no project
        // database: fall back to the standalone rows instead of leaving a
        // wiped list behind. Belt and suspenders with the selectWorkspace
        // early-merge above — whichever path runs, chats stay visible.
        guard projectId != ChatSession.standaloneProjectKey else {
            self.sessions = db.loadStandaloneSessions()
            self.updateSidebarProjectlessSessions(self.sessions)
            return
        }
        guard let targetWorkspace = workspaces.first(where: { $0.id == projectId || $0.path == projectId }) else {
            self.sessions = db.loadStandaloneSessions()
            self.updateSidebarProjectlessSessions(self.sessions)
            return
        }
        let projectPath = targetWorkspace.path
        let loadedSessions = db.loadSessions(projectId: projectPath)

        // A project switch can happen while another load is in flight. Never
        // let the old project's rows overwrite the newly selected project's UI.
        guard WorkspaceSelectionLogic.shouldApplyLoadedSessions(
            selectedID: selectedWorkspace?.id,
            loadedID: targetWorkspace.id
        ) else {
            return
        }

        // Audit 2026-09-09: this used to REPLACE the whole list, wiping the
        // standalone (workspace-less) chats loaded at init — after every
        // restart with a workspace selected, standalone chats vanished from
        // the sidebar ("chat without a project doesn't save"). Merge: project
        // rows win, standalone rows persist. Standalone comes from the
        // DATABASE (not just memory — selectWorkspace clears the list before
        // this load runs, so an in-memory-only union would still wipe).
        let storedStandalone = db.loadStandaloneSessions()
        let standalone = storedStandalone.filter { stored in
            !loadedSessions.contains(where: { loaded in loaded.id == stored.id })
        }
        self.sessions = loadedSessions + standalone
        // Keep the sidebar tree cache in sync: the selected project's chats
        // are already loaded, and the project-less chats live in the global
        // store (F71).
        self.updateSidebarSessions(projectID: targetWorkspace.id, sessions: loadedSessions)
        self.updateSidebarProjectlessSessions(standalone)

        // Convert sessions to workspace tasks
        if let index = workspaces.firstIndex(where: { $0.id == targetWorkspace.id }) {
            let tasks = loadedSessions.map { session in
                WorkspaceTask(
                    id: session.id,
                    title: session.title,
                    status: .inProgress,
                    duration: nil
                )
            }
            workspaces[index].tasks = tasks
        }
    }
    
    /// Создать новый проект/workspace в БД
    @MainActor
    func createOrUpdateProject(id: String, name: String, path: String, gitRemote: String? = nil, gitBranch: String? = nil) {
        db.upsertProject(
            id: id,
            name: name,
            path: path,
            gitRemote: gitRemote,
            gitBranch: gitBranch
        )
        
        // Reload projects
        Task {
            await loadProjectsFromDatabase()
        }
    }
    
    /// Создать новую сессию в БД
    @MainActor
    func createSessionInDatabase(
        id: String,
        projectId: String,
        title: String,
        directory: String,
        branch: String? = nil
    ) {
        guard let projectPath = ProjectSessionRoutingLogic.path(
            projectID: projectId,
            selectedPath: selectedWorkspace?.path,
            workspaces: workspaces.map { ProjectSessionRoutingLogic.WorkspacePath(id: $0.id, path: $0.path) }
        ) else {
            print("❌ Cannot create session without a resolvable project: \(projectId)")
            return
        }
        db.createSession(
            id: id,
            projectId: projectPath,
            title: title,
            directory: directory,
            branch: branch,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        
        // Reload sessions
        Task {
            await loadSessionsFromDatabase(projectId: projectId)
        }
    }
    
    /// Архивировать сессию
    @MainActor
    func archiveSessionInDatabase(id: String) {
        guard db.archiveSession(id: id) else { return }
        removeSessionFromInMemoryState(id: id)
    }
    
    /// Toggle pin статус проекта
    @MainActor
    func toggleProjectPin(projectId: String) {
        db.toggleProjectPin(id: projectId)
        
        // Reload projects
        Task {
            await loadProjectsFromDatabase()
        }
    }
    
    /// Получить API key провайдера из Keychain
    func getProviderAPIKey(providerId: String) -> String? {
        return db.getProviderAPIKey(providerId: providerId)
    }
    
    /// Сохранить новый API key провайдера
    @MainActor
    func saveProviderAPIKey(providerId: String, apiKey: String) {
        db.saveProviderAPIKey(providerId: providerId, apiKey: apiKey)
        
        // Note: CustomProvider.apiKey is non-optional String, so we can't set it to nil
        // The key is now safely stored in Keychain and can be retrieved via getSecureAPIKey()
    }
    
    /// Удалить API key провайдера
    @MainActor
    func deleteProviderAPIKey(providerId: String) {
        db.deleteProviderAPIKey(providerId: providerId)
    }
    
    /// Поиск сообщений через FTS5
    func searchMessagesInDatabase(query: String) -> [String] {
        return db.searchMessages(query: query)
    }
    
    // MARK: - Storage Management
    
    /// Получить статистику хранилища
    @MainActor
    /// Real usage data points from the DB for statistics (plan Раздел 10).
    func loadUsageDataPoints() -> [UsageDataPoint] {
        let legacy = (try? DatabaseManager.shared.usageDataPoints()) ?? []
        let projectPoints = projectPathsForMaintenance.map { path in
            (try? ProjectDatabaseManager.manager(forProjectPath: path).usageDataPoints()) ?? []
        }
        return UsageDataSourcesLogic.merge(legacy: legacy, projects: projectPoints)
    }

}

// MARK: - Models

struct StorageStats {
    let databaseSize: UInt64
    let snapshotSize: UInt64
    let messageCount: Int
    let sessionCountsByProject: [(projectId: String, active: Int, archived: Int)]
    
    var databaseSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(databaseSize), countStyle: .file)
    }
    
    var snapshotSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(snapshotSize), countStyle: .file)
    }
    
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(databaseSize + snapshotSize), countStyle: .file)
    }
    
    var totalActiveSessions: Int {
        sessionCountsByProject.reduce(0) { $0 + $1.active }
    }
    
    var totalArchivedSessions: Int {
        sessionCountsByProject.reduce(0) { $0 + $1.archived }
    }
}

// MARK: - CustomProvider Extension для работы с Keychain

extension CustomProvider {
    /// Получить API key из Keychain вместо plain storage.
    /// Fallback на plain apiKey для обратной совместимости после миграции.
    func getSecureAPIKey() -> String? {
        if let keychainKey = DatabaseBridge.shared.getProviderAPIKey(providerId: self.id) {
            return keychainKey
        }
        // Fallback to plain storage for backward compatibility
        return apiKey.isEmpty ? nil : apiKey
    }
}
