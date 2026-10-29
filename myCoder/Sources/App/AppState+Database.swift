// DatabaseManager integration extension for AppState
import Foundation
import AppKit
import UniformTypeIdentifiers

extension AppState {
    
    /// Получить доступ к DatabaseBridge
    private var db: DatabaseBridge {
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

    func loadStorageStats() -> StorageStats {
        let globalCounts = (try? DatabaseManager.shared.sessionCountsByProject()) ?? []
        let globalSnapshot = ProjectStorageStatsLogic.Snapshot(
            databaseSize: DatabaseManager.shared.databaseFileSize(),
            messageCount: (try? DatabaseManager.shared.messageCount()) ?? 0,
            active: globalCounts.reduce(0) { $0 + $1.active },
            archived: globalCounts.reduce(0) { $0 + $1.archived },
            projectID: ProjectStorageStatsLogic.globalIdentifier
        )
        let projectSnapshots = projectPathsForMaintenance.compactMap { path -> ProjectStorageStatsLogic.Snapshot? in
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path),
                  let sessions = try? projectDB.getAllSessions(includeArchived: true) else {
                return nil
            }
            return ProjectStorageStatsLogic.Snapshot(
                databaseSize: projectDB.databaseFileSizeBytes(),
                messageCount: (try? projectDB.messageCount()) ?? 0,
                active: sessions.filter { !$0.isArchived }.count,
                archived: sessions.filter(\.isArchived).count,
                projectID: path
            )
        }
        let aggregate = ProjectStorageStatsLogic.aggregate(
            global: globalSnapshot,
            projects: projectSnapshots,
            snapshotSize: FileSnapshotManager.shared.snapshotsSizeBytes()
        )
        return StorageStats(
            databaseSize: aggregate.databaseSize,
            snapshotSize: aggregate.snapshotSize,
            messageCount: aggregate.messageCount,
            sessionCountsByProject: aggregate.sessionCounts.map {
                (projectId: $0.projectID, active: $0.active, archived: $0.archived)
            }
        )
    }
    
    private var projectPathsForMaintenance: [String] {
        var paths = Set(workspaces.map { ChatSession.normalizedPath($0.path) })
        if let selectedPath = selectedWorkspace?.path {
            paths.insert(ChatSession.normalizedPath(selectedPath))
        }
        return paths.sorted()
    }

    private func refreshProjectSessionUI() {
        Task { @MainActor in
            await loadProjectsFromDatabase()
            if let projectID = selectedWorkspace?.id {
                await loadSessionsFromDatabase(projectId: projectID)
            }
        }
    }

    /// Archive sessions older than N days in the legacy store and every loaded
    /// project database. The legacy pass preserves history created before the
    /// per-project storage migration; project DBs are the canonical path now.
    func archiveOldSessions(days: Int) {
        try? StorageAuditLog.append(action: "sessions.archive_old",
                                    detail: "days=\(days)",
                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        _ = try? DatabaseManager.shared.archiveSessionsOlderThan(days: days)
        for path in projectPathsForMaintenance {
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path) else { continue }
            _ = try? projectDB.archiveSessionsOlderThan(days: days)
        }
        refreshProjectSessionUI()
    }

    /// Permanently delete archived sessions from the legacy store and every
    /// loaded project database.
    func deleteArchivedSessions() -> Int {
        try? StorageAuditLog.append(action: "sessions.delete_archived",
                                    detail: "all",
                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        var count = (try? DatabaseManager.shared.deleteArchivedSessions()) ?? 0
        for path in projectPathsForMaintenance {
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path) else { continue }
            let deleted = (try? projectDB.deleteArchivedSessions()) ?? 0
            count += deleted
            if deleted > 0 { _ = try? projectDB.vacuum() }
        }
        if count > 0 { try? DatabaseManager.shared.vacuum() }
        if count > 0 { refreshProjectSessionUI() }
        return count
    }

    /// Permanently delete sessions older than N days from the legacy store and
    /// every loaded project database.
    func deleteSessionsOlderThan(days: Int) -> Int {
        try? StorageAuditLog.append(action: "sessions.delete_older",
                                    detail: "days=\(days)",
                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        var count = (try? DatabaseManager.shared.deleteSessionsOlderThan(days: days)) ?? 0
        for path in projectPathsForMaintenance {
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path) else { continue }
            let deleted = (try? projectDB.deleteSessionsOlderThan(days: days)) ?? 0
            count += deleted
            if deleted > 0 { _ = try? projectDB.vacuum() }
        }
        if count > 0 { try? DatabaseManager.shared.vacuum() }
        if count > 0 { refreshProjectSessionUI() }
        return count
    }

    /// Clears in-memory selection/navigation/sessions/projects (no DB I/O).
    /// Round 10 — the crash fix is verifiable without touching the real
    /// database, so tests never race on ~/.mycoder/mycoder.db.
    func clearInMemoryState() {
        selectedSession = nil
        selectedWorkspace = nil
        sessions = []
        projects = []
        clearNavigationHistory()
    }

    /// Reset storage by explicit scope (plan Раздел 8 Блок 1 п.10).
    /// Honest, predictable behavior: deletes exactly the planned paths and
    /// clears selection/navigation.
    ///
    /// Round 14 (test-safety): `homeDirectory` is injectable so tests sandbox
    /// the reset to a temp dir instead of the REAL user home (the old
    /// StorageResetCrashTests deleted the real ~/.mycoder/mycoder.db).
    /// `resetDatabase` is a closure so tests can substitute a no-op and never
    /// touch `DatabaseManager.shared`.
    func resetStorage(scope: StorageResetScope,
                      homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                      projectPaths: [String] = [],
                      resetDatabase: () -> Void = { try? DatabaseManager.shared.wipeAndReopen() }) {
        let home = homeDirectory
        let plan = StorageResetLogic.plan(
            for: scope,
            homeDirectory: home,
            projectPaths: projectPaths
        )

        // Audit the reset (plan Раздел 8 п.46) BEFORE the deletion so the log
        // survives any crash mid-reset.
        try? StorageAuditLog.append(action: "storage.reset",
                                    detail: "scope=\(plan.scope) paths=\(plan.deletesPaths.joined(separator: ", "))",
                                    homeDirectory: home)

        if scope == .fullDatabase {
            // Drop every pooled project connection before its file disappears,
            // otherwise a stale inode could keep serving deleted data.
            ProjectDatabaseManager.evictAll()
        }

        // Delete exactly the planned paths and their SQLite sidecars
        // (-journal/-wal/-shm). The live connection is still open for this
        // brief instant; the default `resetDatabase` closure immediately closes
        // it (wipeAndReopen) so the deleted inode can never poison later
        // statements, and `SQLiteSafeQuery` makes any transient error during
        // the window throw instead of crash (SIGILL).
        for path in plan.deletesPaths {
            try? FileManager.default.removeItem(atPath: path)
            for suffix in ["-journal", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        // Reinitialize the app database (recreates the cleared mycoder.db on
        // disk). Default = wipeAndReopen(): closes the stale open handle to
        // the removed file, ensures the file+sidecars are gone, and opens a
        // brand-new empty database. Tests substitute a no-op closure so the
        // real singleton is never touched.
        resetDatabase()

        clearInMemoryState()

        Task { @MainActor in
            await loadProjectsFromDatabase()
        }
    }

    /// Сбросить базу данных
    func resetDatabase() {
        try? DatabaseManager.shared.reset()
        Task { @MainActor in
            await loadProjectsFromDatabase()
            sessions = []
        }
    }
    
    /// Сжать legacy and every project-scoped database (VACUUM).
    func vacuumDatabase() {
        try? DatabaseManager.shared.vacuum()
        for path in projectPathsForMaintenance {
            guard let projectDB = try? ProjectDatabaseManager.manager(forProjectPath: path) else { continue }
            _ = try? projectDB.vacuum()
        }
    }

    /// Сжать per-project БД конкретного проекта (plan Раздел 8 п.28).
    /// Автобэкап перед VACUUM (plan Раздел 8 п.49) — на случай повреждения
    /// при сжатии остаётся рабочая копия.
    func vacuumProject(path: String) -> Bool {
        _ = try? ProjectAutoBackupLogic.createBackup(projectPath: path)
        _ = try? ProjectAutoBackupLogic.prune(projectPath: path)
        guard let db = try? ProjectDatabaseManager.manager(forProjectPath: path) else { return false }
        do {
            try db.vacuum()
            return true
        } catch {
            return false
        }
    }

    /// Export the current project's full history via ProjectHistoryExporter.
    /// This wires the exporter into live code so it is no longer an orphan
    /// (Round 7 orphan-wiring requirement).
    func exportProjectHistory() -> Data? {
        guard let path = selectedWorkspace?.path,
              let db = try? ProjectDatabaseManager.manager(forProjectPath: path) else { return nil }
        return try? ProjectHistoryExporter.export(from: db)
    }

    /// Import a previously exported project history bundle.
    @discardableResult
    func importProjectHistory(_ data: Data) -> ProjectHistoryExporter.ImportSummary? {
        guard let path = selectedWorkspace?.path,
              let db = try? ProjectDatabaseManager.manager(forProjectPath: path) else { return nil }
        return try? ProjectHistoryExporter.importBundle(data, into: db)
    }
    
    /// Архивировать сессию и обновить UI
    func archiveSessionInDatabaseUI(id: String) {
        db.archiveSession(id: id)
        if let projectId = selectedWorkspace?.id {
            Task { @MainActor in
                await loadSessionsFromDatabase(projectId: projectId)
            }
        }
    }
    
    /// Разархивировать сессию
    func unarchiveSessionInDatabase(id: String) {
        try? DatabaseManager.shared.unarchiveSession(id: id)
        if let projectId = selectedWorkspace?.id {
            Task { @MainActor in
                await loadSessionsFromDatabase(projectId: projectId)
            }
        }
    }

    // MARK: - Session row actions (rename / share / export / delete)

    /// Rename a chat from the sidebar. Updates the owning store first and the
    /// in-memory list only after the DB write succeeds, so the UI can never
    /// show a title that was not persisted.
    @MainActor
    func renameSessionInDatabaseUI(id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard db.renameSession(id: id, title: trimmed) else {
            shellActionNotice = "Could not rename the chat — it is no longer in the database."
            shellActionNoticeTone = .error
            return
        }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].title = trimmed
        }
        if selectedSession?.id == id {
            selectedSession?.title = trimmed
        }
    }

    /// Hard-delete a chat from the sidebar. Dependent rows (messages, parts,
    /// tool calls) are removed explicitly in the DB; the in-memory list is
    /// updated only after a successful delete.
    @MainActor
    func deleteSessionInDatabaseUI(id: String) {
        guard db.deleteSession(id: id) else { return }
        // The sidebar tree renders its own caches, so removing the chat from
        // `sessions` alone left a dead row that opened an empty chat.
        removeSessionFromInMemoryState(id: id)
    }

    /// Full transcript (Markdown) for Share/Export, read from the store that
    /// owns the session.
    func sessionTranscriptMarkdown(sessionId: String) -> String? {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return nil }
        let messages = DatabaseBridge.shared.loadMessageTail(sessionId: sessionId, take: nil)
        return SessionTranscriptLogic.markdown(title: session.title, messages: messages)
    }

    /// Save the transcript through a real save panel. Returns nil when the
    /// user cancels or the write fails.
    @MainActor
    @discardableResult
    func exportSessionTranscript(sessionId: String) -> URL? {
        guard let markdown = sessionTranscriptMarkdown(sessionId: sessionId),
              let session = sessions.first(where: { $0.id == sessionId }) else { return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = SessionTranscriptLogic.fileName(title: session.title)
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            shellActionNotice = "Could not export transcript: \(error.localizedDescription)"
            shellActionNoticeTone = .error
            return nil
        }
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
