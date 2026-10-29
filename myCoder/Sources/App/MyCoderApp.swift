import SwiftUI
import Foundation
import AppKit
#if canImport(WebKit)
import WebKit
#endif

/// Global reference for local API server access. Set during app startup.
var __myCoderAppState: AppState?

/// One-shot coder prompt waiting for its chat history to finish loading.
/// AppState owns it so the wizard can start a task from any view.
struct PendingSpecNodePrompt: Equatable {
    let id: String
    let sessionID: String
    let text: String
}

@main
struct MyCoderApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    __myCoderAppState = appState
                    StuckCursorFix.install()
                    MyCoderAPIServer.shared.start()
                }
                .frame(minWidth: 900, idealWidth: 1200, maxWidth: .infinity,
                       minHeight: 600, idealHeight: 750, maxHeight: .infinity)
                .background(Color.mimo.background)
        }
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button(L.t(AppLocalizationKey.locCut)) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(L.t(AppLocalizationKey.locCopy)) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(L.t(AppLocalizationKey.locPaste)) {
                    _ = ChatPasteCoordinator.shared.performPaste()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                // Replacing .pasteboard removes the standard Select All item;
                // re-add it or Cmd+A is dead in every text field.
                Button(L.t(AppLocalizationKey.locSelectAll)) {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(L.t(AppLocalizationKey.locNewTask)) {
                    appState.startNewTask(in: appState.selectedWorkspace)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(L.t(AppLocalizationKey.locFind)) {
                Button(L.t(AppLocalizationKey.locSearchTasks)) {
                    appState.showSearch = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu(L.t(AppLocalizationKey.locActions)) {
                Button(L.t(AppLocalizationKey.locUndoLastFileChange)) {
                    appState.undoLastAction()
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(appState.selectedSession == nil)
            }
        }
    }
}

enum ProjectCreationMode: String, CaseIterable {
    case empty
    case wizard
}

class AppState: ObservableObject {
    let instanceID = UUID().uuidString.prefix(8)
    deinit {
        if let observer = subagentObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = autoFreeSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = providersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        MyCoderAPIServer.appendLog("💀 AppState.deinit: id=\(instanceID)")
    }
    /// The UserDefaults instance used for persistence.  Public so tests can
    /// inject a dedicated instance (e.g. `UserDefaults(suiteName:)`) instead
    /// of racing on the shared `.standard` domain.
    var defaults: UserDefaults = .standard

    @Published var selectedProject: Project?
    @Published var selectedTask: TaskItem?
    @Published var projects: [Project] = []
    @Published var sessions: [ChatSession] = []
    @Published var selectedSession: ChatSession?
    @Published var showTerminal = false
    @Published var showGoal = false {
        didSet {
            defaults.set(showGoal, forKey: "com.mycoder.showGoal")
        }
    }
    /// Monotonic counter; incremented to move keyboard focus into the message input.
    @Published var inputFocusRequest = 0
    /// Enable the in-input command palette dropdown (plan Раздел 6 Блок 3 п.30).
    @Published var inputDropdownEnabled = true
    @Published var showSearch = false
    @Published var showProjectCreation = false
    /// Distinguishes the two entries in the sidebar's New Project dropdown:
    /// a plain project (chat immediately) or a spec-wizard project (chat is
    /// gated until the project specification is finished or force-finished).
    @Published var projectCreationMode: ProjectCreationMode = .empty
    /// Project whose spec wizard is currently blocking the chat area.
    @Published var activeSpecWizardProjectPath: String?
    /// Paths the user explicitly left this session. Restarting the app forgets
    /// this, so an unfinished draft still gates chat after a relaunch.
    private var dismissedSpecWizardPaths: Set<String> = []
    /// Coder prompt that must be sent once the selected chat is loaded.
    @Published var pendingSpecNodePrompt: PendingSpecNodePrompt?
    @Published var isStreaming = false
    @Published var isLoading = false
    /// Sessions with a live model turn (streaming or waiting for a plan
    /// question). The sidebar shows an activity indicator on those rows, so a
    /// turn that keeps running in the background stays visible while the user
    /// reads another chat.
    @Published var streamingSessionIDs: Set<String> = []
    /// True while the host compiles the point context for the next send
    /// (user directive D1: the loader says "собираем точечный контекст").
    @Published var isCompilingContext = false
    /// Whether the point context is compiled before every send. On by default:
    /// compilation is deterministic and local, and without it the send carries
    /// no evidence at all.
    @Published var isPointContextEnabled: Bool = true {
        didSet {
            defaults.set(isPointContextEnabled, forKey: "com.mycoder.pointContextEnabled")
        }
    }
    /// Whether the optional local model plans the query before the host
    /// compiles the context. Off by default: the local model may be slow or
    /// absent, while the deterministic plan always works.
    @Published var isLocalQueryPlannerEnabled: Bool = LocalPlannerSettings.defaultEnabled {
        didSet {
            defaults.set(isLocalQueryPlannerEnabled, forKey: LocalPlannerSettings.storageKey)
        }
    }
    @Published var selectedModel = ""
    @Published var selectedProviderID = ""
    @Published private(set) var providerConnectivity: [String: Bool] = [:]
    @Published var maxTokens = true
    @Published var askBeforeChanges = true
    @Published var sidebarVisible = true
    
    @Published var serverConnected = false
    @Published var serverHost = "127.0.0.1"
    @Published var serverPort = 4096
    var availableModels: [String] {
        ProviderSettingsLogic.mergeModelIDs(
            serverProviders: serverProviders,
            customProviders: customProviders,
            isDisabled: { [defaults] providerID, modelID in
                DisabledModelStore.isDisabled(
                    providerID: providerID,
                    modelID: modelID,
                    defaults: defaults
                )
            }
        )
    }
    @Published var serverProviders: [MimoProviderResponse] = []
    @Published var customProviders: [CustomProvider] = []
    /// Per-provider result of the last model refresh. Exposed in Settings so a
    /// bad URL, authentication failure, or unsupported response is actionable
    /// instead of looking like a mysterious empty model list.
    @Published private(set) var providerModelLoadMessages: [String: String] = [:]
    /// Bumped whenever a local/web provider config or custom-provider list is
    /// saved. Provider options are computed from disk-backed stores, so without
    /// this SwiftUI would not re-render the chat model menu after a Settings
    /// refresh (plan Раздел 1 п.3).
    @Published private(set) var providerCatalogRevision = 0

    @Published var workspaces: [Workspace] = []
    /// Lightweight registry snapshot used to reconcile sidebar visibility with
    /// Storage archive actions without hiding an unknown legacy workspace.
    @Published private(set) var projectRegistryEntries: [ProjectRegistryEntry] = []
    private var isNavigatingHistory = false
    /// Pending message from local API. ChatPanelView observes this to trigger sends.
    @Published var apiPendingMessage: String?
    
    /// Guards navigationHistory/navigationIndex mutations. The `selectedWorkspace`
    /// didSet can fire from any thread (tests, background init tasks), so the
    /// truncate+append must be atomic or removeSubrange races into an
    /// out-of-range fatal error (Round 10 crash, still reproduced under parallel
    /// test runs — now fixed with a real lock, not just a bounds check).
    private let navigationLock = NSLock()
    
    @Published var selectedWorkspace: Workspace? {
        didSet {
            if ProjectFileIndexWatcherLifecycleLogic.shouldRestart(
                oldProjectPath: oldValue?.path,
                newProjectPath: selectedWorkspace?.path
            ) {
                updateProjectFileIndexWatcher(for: selectedWorkspace)
            }
            guard let workspace = selectedWorkspace else { return }

            // E04 (Раздел 8 п.48): open-time integrity check — a corrupted
            // per-project DB must surface an offer to restore the latest
            // backup instead of silently crashing or serving stale data.
            let path = workspace.path
            Task.detached(priority: .utility) {
                if case .corrupt(let message) = ProjectOpenIntegrity.checkOnOpen(projectPath: path) {
                    let alert = ProjectIntegrityAlert(projectPath: path, message: message)
                    await MainActor.run { self.projectIntegrityAlert = alert }
                }
            }

            navigationLock.lock()
            guard !isNavigatingHistory else {
                navigationLock.unlock()
                return
            }
            if navigationHistory.isEmpty || navigationHistory.last?.id != workspace.id {
                // Atomically recompute the safe truncation point under the lock:
                // both the bounds check AND the mutation now happen on the same
                // thread, so a concurrent didSet can't interleave.
                if navigationIndex >= 0 && navigationIndex < navigationHistory.count {
                    let cutoff = navigationIndex + 1
                    if cutoff < navigationHistory.count {
                        navigationHistory.removeSubrange(cutoff..<navigationHistory.count)
                    } else {
                        navigationHistory = [navigationHistory[navigationIndex]]
                    }
                }
                navigationHistory.append(workspace)
                navigationIndex = navigationHistory.count - 1
            }
            navigationLock.unlock()
        }
    }
    @Published var navigationHistory: [Workspace] = []
    @Published var navigationIndex: Int = -1

    /// Reset navigation to a safe state (used when the workspace is cleared,
    /// e.g. during a storage reset) so the UI can't observe an out-of-bounds
    /// index into navigationHistory. Internal so extensions (AppState+Database)
    /// can call it.
    func clearNavigationHistory() {
        navigationLock.lock()
        navigationHistory = []
        navigationIndex = -1
        navigationLock.unlock()
    }
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
        }
    }

    var appLanguage: AppLanguage {
        AppLanguage.from(stored: settings.language)
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func setLanguage(_ language: AppLanguage) {
        updateSettings { $0.language = language.rawValue }
        LocalizationRuntime.currentLanguage = language
        // Force UI refresh by bumping the language counter
        objectWillChange.send()
    }
    @Published var accessLevel: AccessLevel = .askBeforeChanges {
        didSet {
            guard !isSyncingAccessLevel else { return }
            defaults.set(accessLevel.rawValue, forKey: "com.mycoder.accessLevel")
            Task { await applyAccessLevelToServer() }
        }
    }
    @Published var selectedVariant: String = "high" {
        didSet {
            defaults.set(selectedVariant, forKey: "com.mycoder.selectedVariant")
        }
    }
    @Published var agentMode: AgentMode = .build {
        didSet {
            defaults.set(agentMode.rawValue, forKey: "com.mycoder.agentMode")
        }
    }
    @Published var showSettings = false
    @Published var showRemoteConnection = false
    @Published var settingsTab: SettingsTab = .general
    @Published var currentSteps: [TaskStep] = []
    @Published var pendingQuestionRequest: PendingQuestionRequest?
    @Published var vcsChanges: [MimoVcsFileDiff] = []
    @Published var sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
    /// Sub-agent chats of the selected session, shown in the right panel
    /// between the GitHub tools and the plan. Clicking a row navigates into
    /// the child chat transcript.
    @Published var subagentSessions: [ChatSession] = []
    @Published var gitBranch = "main"
    @Published var gitBranches: [String] = []
    @Published var gitStatusMessage: String?
    /// Set by slash commands (`/commit`, `/pr`, `/review`) to open the
    /// corresponding git dialog (E08, Раздел 5 п.13/15/16). ContentView
    /// presents one `.sheet(item:)` that switches on this value.
    @Published var pendingGitAction: GitUIAction?
    /// Set when a project is opened and its database fails the open-time
    /// integrity check (E04, Раздел 8 п.48). ContentView offers to restore
    /// the latest auto-backup.
    @Published var projectIntegrityAlert: ProjectIntegrityAlert?
    @Published var isGitBusy = false
    @Published var gitRepositoryPath: String?
    @Published var workspaceSortOrder: WorkspaceSortOrder = .recentUse
    @Published var workspaceViewMode: WorkspaceViewMode = .list
    @Published var workspaceFilterQuery: String = ""
    @Published var workspaceFilterPreset: WorkspaceFilterPreset = .all
    @Published var showWorkspaceSearchField = false
    @Published var workspacesSectionExpanded = true
    /// Chats of every project, keyed by project id. Loaded per project so the
    /// sidebar can show every project's children instead of only the selected
    /// project's (F71).
    @Published private(set) var sidebarProjectSessions: [String: [ChatSession]] = [:]
    /// Chats that belong to no project. Each one becomes its own top-level
    /// sidebar row (F71).
    @Published private(set) var sidebarProjectlessSessions: [ChatSession] = []
    /// Sidebar rows pinned to the top (project ids and project-less chat ids).
    @Published private(set) var pinnedSidebarItemIDs: Set<String> = []
    /// Quick archive popover from the sidebar (plan Раздел 11 Блок 2 п.16).
    @Published var showArchivePopover = false
    @Published var showNotifications = false
    @Published var showWorkspacesOverview = false
    @Published var showBranchPicker = false
    @Published var showRemoveProviderConfirmation = false
    @Published var pendingProviderToDelete: CustomProvider?
    @Published var notificationService = NotificationService()
    /// One-shot "show this message" request raised by a notification tap.
    /// ChatPanelView consumes it after the target chat's history is loaded.
    @Published private(set) var messageFocusRequest: MessageFocusRequest?
    @Published var transientProviderNotification: AppNotification? = nil
    /// Short-lived feedback for shell actions such as Cmd+Option+Z.
    @Published var shellActionNotice: String?
    @Published var shellActionNoticeTone: UndoActionFeedbackTone = .success
    private var autoFreeSwitchObserver: NSObjectProtocol?
    private var providersObserver: NSObjectProtocol? = nil
    private var subagentObserver: NSObjectProtocol? = nil
    
    var displayedWorkspaces: [Workspace] {
        let visible = WorkspaceArchiveVisibilityLogic.visible(
            workspaces,
            registry: projectRegistryEntries,
            selectedPath: selectedWorkspace?.path
        )
        let known = sidebarKnownSessions
        let nameFiltered = SidebarWorkspaceLogic.filtered(visible, query: workspaceFilterQuery)
        let sessionFiltered = SidebarWorkspaceLogic.filteredBySessionCount(nameFiltered, sessions: known, preset: workspaceFilterPreset)
        return SidebarWorkspaceLogic.sorted(sessionFiltered, order: workspaceSortOrder, sessions: known)
    }

    /// Every chat the sidebar knows about: all projects' chats plus the
    /// project-less ones. Used for the sidebar's filters and sorting, so a
    /// non-selected project is not counted as empty (F71).
    var sidebarKnownSessions: [ChatSession] {
        var byID: [String: ChatSession] = [:]
        for session in sessions { byID[session.id] = session }
        for projectSessions in sidebarProjectSessions.values {
            for session in projectSessions { byID[session.id] = session }
        }
        for session in sidebarProjectlessSessions { byID[session.id] = session }
        return Array(byID.values)
    }

    /// The sidebar tree: projects (with their chats) plus one top-level row
    /// per chat without a project. Built in a single pass so every chat has
    /// exactly one parent (F71).
    var sidebarTreeItems: [SidebarTreeItem] {
        SidebarTreeBuilder.build(
            workspaces: displayedWorkspaces,
            sessionsByWorkspaceID: sidebarProjectSessions,
            projectlessSessions: sidebarProjectlessSessions,
            pinnedIDs: pinnedSidebarItemIDs
        )
    }

    /// Chats of one project for the sidebar. The selected project answers
    /// from the in-memory list, other projects from their own database.
    func sidebarSessions(for workspace: Workspace) -> [ChatSession] {
        if let cached = sidebarProjectSessions[workspace.id] {
            return cached
        }
        return sessions.filter { $0.belongs(to: workspace) }
    }

    /// Load one project's chats for the sidebar (once per project).
    @MainActor
    func loadSidebarSessions(for workspace: Workspace) {
        guard sidebarProjectSessions[workspace.id] == nil else { return }
        let path = workspace.path
        let id = workspace.id
        Task { @MainActor in
            let loaded = DatabaseBridge.shared.loadSessions(projectId: path)
            sidebarProjectSessions[id] = loaded
        }
    }

    /// Store one project's chats for the sidebar tree.
    @MainActor
    func updateSidebarSessions(projectID: String, sessions: [ChatSession]) {
        sidebarProjectSessions[projectID] = sessions
    }

    /// Store the chats that belong to no project.
    @MainActor
    func updateSidebarProjectlessSessions(_ sessions: [ChatSession]) {
        sidebarProjectlessSessions = sessions
    }

    /// Reload the chats that belong to no project.
    @MainActor
    func refreshSidebarProjectlessSessions() {
        sidebarProjectlessSessions = DatabaseBridge.shared.loadStandaloneSessions()
    }

    /// Pin or unpin a sidebar row (project or project-less chat).
    @MainActor
    func toggleSidebarPin(id: String) {
        if pinnedSidebarItemIDs.contains(id) {
            pinnedSidebarItemIDs.remove(id)
        } else {
            pinnedSidebarItemIDs.insert(id)
        }
        SidebarPinStore.save(pinnedSidebarItemIDs, defaults: defaults)
    }

    /// Reload the global project registry after Storage/Archive mutations so
    /// the sidebar reflects the action immediately instead of requiring a
    /// relaunch. Unknown registry rows remain non-destructive to workspaces.
    @MainActor
    func refreshProjectRegistry() {
        projectRegistryEntries = ProjectRegistryStore.load()
    }
    
    var userDisplayName: String { UserProfileDisplay.displayName() }
    var userInitials: String { UserProfileDisplay.initials(from: userDisplayName) }
    @Published var appTheme: AppTheme = .dark {
        didSet {
            defaults.set(appTheme.rawValue, forKey: "com.mycoder.theme")
            Color.mimo.setTheme(appTheme)
        }
    }
    
    var mimoClient: MimoServeClient
    private var isSyncingAccessLevel = false
    private let gitRefreshCoalescer = GitRefreshCoalescer()
    private var gitBusyCount = 0
    
    // Database integration
    private var dbBridge: DatabaseBridge {
        DatabaseBridge.shared
    }

    /// Per-project undo manager, created lazily when a workspace is active.
    /// Replaces the legacy global `UndoRedoManager` (Round 7).
    var projectUndoManager: ProjectUndoManager? {
        guard let path = selectedWorkspace?.path else { return nil }
        return try? ProjectUndoManager(projectPath: path)
    }

    /// Audit 2026-09-13 (user DB pollution): the XCTest check missed
    /// swift-testing runs entirely — `swift test` does NOT link XCTest into
    /// the runner process, so the old detector returned false in CI/local
    /// `swift test`. The shared `TestRunDetector` now also probes the
    /// swift-testing runtime classes.
    private static let isRunningTests: Bool = TestRunDetector.isRunningTests

    /// Sandbox root for auxiliary per-person files (audit log, legacy
    /// registry import) when running tests. Project state itself lives in the
    /// database, which is in-memory under the test runner.
    let registryHomeDirectory: URL

    // MiMo Serve connection manager (now optional)
    @Published var serverConnectionManager: MimoServeConnectionManager?

    init(host: String = "127.0.0.1", port: Int = 4096, defaults: UserDefaults = .standard) {
        self.registryHomeDirectory = Self.isRunningTests
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("mycoder-test-home-\(UUID().uuidString)", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser
        // Clean slate (user directive): provider rows, API keys and model
        // selections from an earlier project must never leak into this build.
        // Runs once, before any persisted provider value is read.
        if !Self.isRunningTests {
            ProviderCleanSlateReset.runIfNeeded(defaults: defaults)
        }
        let initialHost = Self.isRunningTests
            ? host
            : (defaults.string(forKey: ServerProviderCatalogStore.hostKey)
                .flatMap { $0.isEmpty ? nil : $0 } ?? host)
        let initialPort = Self.isRunningTests
            ? port
            : (defaults.object(forKey: ServerProviderCatalogStore.portKey) as? Int ?? port)
        self.serverHost = initialHost
        self.serverPort = initialPort
        self.mimoClient = MimoServeClient(host: initialHost, port: initialPort)
        self.serverConnectionManager = MimoServeConnectionManager(client: mimoClient)
        self.defaults = defaults
        MyCoderAPIServer.appendLog("🆕 AppState.init: id=\(instanceID)")

        // Load persisted values from the injected defaults domain
        selectedModel = defaults.string(forKey: "com.mycoder.selectedModel") ?? ""
        selectedProviderID = defaults.string(forKey: "com.mycoder.selectedProviderID") ?? ""
        isPointContextEnabled = defaults.object(forKey: "com.mycoder.pointContextEnabled") as? Bool ?? true
        isLocalQueryPlannerEnabled = LocalPlannerSettings.isEnabled(in: defaults)
        showGoal = defaults.bool(forKey: "com.mycoder.showGoal")
        selectedVariant = {
            if let saved = defaults.string(forKey: "com.mycoder.selectedVariant"), !saved.isEmpty {
                return saved
            }
            let legacy = defaults.string(forKey: "com.mycoder.thinkingLevel") ?? ""
            return ProviderSettingsLogic.migrateLegacyThinkingLevel(legacy) ?? "high"
        }()
        agentMode = {
            let raw = defaults.string(forKey: "com.mycoder.agentMode") ?? ""
            return AgentMode(rawValue: raw) ?? .build
        }()
        accessLevel = {
            let raw = defaults.string(forKey: "com.mycoder.accessLevel") ?? ""
            return AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: raw)
        }()
        appTheme = {
            let raw = defaults.string(forKey: "com.mycoder.theme") ?? ""
            return AppTheme(rawValue: raw) ?? .dark
        }()
        pinnedSidebarItemIDs = SidebarPinStore.load(defaults: defaults)
        // settings is already loaded by its own didSet-based persistence
        // Sync LocalizationRuntime with the loaded language
        LocalizationRuntime.currentLanguage = appLanguage

        migrateLegacyPreferences()
        autoFreeSwitchObserver = NotificationCenter.default.addObserver(
            forName: .myCoderAutoFreeModelSwitched,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let appNotification = MyCoderAutoFreeNotificationLogic.make(
                userInfo: notification.userInfo ?? [:]
            )
            self.notificationService.add(appNotification)
            self.transientProviderNotification = appNotification
        }

        providersObserver = NotificationCenter.default.addObserver(
            forName: .providersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.providerCatalogRevision &+= 1
        }

        subagentObserver = NotificationCenter.default.addObserver(
            forName: .subagentSessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSubagentSessions()
        }

        guard !Self.isRunningTests else { return }

        // Initialize database and perform migrations
        Task {
            await initializeDatabase()
            // Attempt server connection (non-blocking) — only when the user
            // explicitly connected to a server before. An automatic probe
            // would import another tool's provider catalog (user directive).
            if Self.serverConnectionEnabled(defaults: defaults) {
                serverConnectionManager?.attemptConnection()
            }
        }
    }

    /// The server connection is opt-in: the app never connects to a local
    /// agent on its own, because that agent's provider catalog would show up
    /// as providers the user never added.
    static func serverConnectionEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "com.mycoder.serverConnectionEnabled")
    }

    private func migrateLegacyPreferences() {
        let rawAccess = defaults.string(forKey: "com.mycoder.accessLevel") ?? ""
        if AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: rawAccess) {
            agentMode = .plan
            defaults.set(AgentMode.plan.rawValue, forKey: "com.mycoder.agentMode")
            defaults.set(AccessLevel.askBeforeChanges.rawValue, forKey: "com.mycoder.accessLevel")
        }

        // The legacy anonymous provider was renamed after its Xiaomi channel sunset.
        // Preserve an existing explicit selection across the rename.
        for key in ["com.mycoder.selectedProviderID", "com.mycoder.preferredProviderID"] {
            let value = defaults.string(forKey: key)
            if value == "mimo-auto" || value == MyCoderAutoFreeProvider.builtInID {
                defaults.removeObject(forKey: key)
            }
        }
    }
    
    func connectToServer() async {
        // The startup probe runs only for an explicitly enabled connection.
        // Without it the app stays offline until the user connects from the
        // Remote connection sheet — no foreign provider catalog appears.
        guard Self.serverConnectionEnabled(defaults: defaults) else {
            await MainActor.run {
                self.serverConnected = false
            }
            return
        }
        // Complete the health check before deciding whether server-backed
        // models may load. Previously the manager became connected while this
        // AppState boolean stayed false, so ContentView skipped model loading
        // on a healthy server during the first startup task.
        await serverConnectionManager?.checkAvailability()
        let managerConnected = serverConnectionManager?.isConnected == true
        let newServerConnected = ServerConnectionReadinessLogic.appStateConnectionState(
            isConnected: serverConnected,
            healthHealthy: managerConnected
        )
        await MainActor.run {
            serverConnected = newServerConnected
        }

        if serverConnected {
            await syncAccessLevelFromServer()
        }
    }
    
    func loadSessionsFromServer() async {
        // Sessions come from the local DB, then optionally from a server the
        // user is already running on localhost. We NEVER spawn a `mimo` CLI or
        // launch `mimo serve` ourselves — the app is fully decoupled from MiMo.
        // 1. Load from the local database.
        await loadProjectsFromDatabase()

        // 2. Optionally sync with a server if the user has one running.
        if serverConnectionManager?.isConnected == true {
            let adapter = ServerToLocalMigrationAdapter(client: mimoClient)
            if let workspace = selectedWorkspace {
                let syncedSessions = await adapter.loadSessions(projectId: workspace.id)
                await MainActor.run {
                    if !syncedSessions.isEmpty {
                        // Audit 2026-09-09: never wipe standalone chats on
                        // server sync (same loss as the project-DB load).
                        // Sourced from the database — the in-memory list may
                        // be mid-reload when the sync lands.
                        let storedStandalone = DatabaseBridge.shared.loadStandaloneSessions()
                        let standalone = storedStandalone.filter { stored in
                            !syncedSessions.contains(where: { synced in synced.id == stored.id })
                        }
                        self.sessions = syncedSessions + standalone
                    }
                }
            }
        }
    }
    
    func loadModelsFromServer() async {
        do {
            let providers = try await mimoClient.providers()
            await MainActor.run {
                self.serverProviders = providers
                ServerProviderCatalogStore.save(providers, defaults: self.defaults)
                self.validateAndReconcileSelections()
            }
        } catch {
            print("Failed to load models: \(error)")
        }
    }

    var providerOptions: [ProviderOption] {
        buildProviderOptions(includeDisabled: false)
    }

    /// Provider list for Settings: disabled custom/local providers stay
    /// visible so they can be re-enabled. The send picker keeps using
    /// `providerOptions`, which only exposes enabled providers.
    var manageableProviderOptions: [ProviderOption] {
        buildProviderOptions(includeDisabled: true)
    }

    private func buildProviderOptions(includeDisabled: Bool) -> [ProviderOption] {
        ProviderDuplicationLogic.deduplicatedOptions(
            rawProviderOptions(includeDisabled: includeDisabled)
        )
    }

    private func rawProviderOptions(includeDisabled: Bool) -> [ProviderOption] {
        var options = ProviderSettingsLogic.allProviderOptions(
            serverProviders: serverProviders,
            customProviders: customProviders,
            includeDisabled: includeDisabled
        ).map { option in
            guard let custom = customProviders.first(where: { $0.id == option.id }),
                  custom.type == .openCodeZen else {
                return option
            }
            return ProviderOption(
                id: option.id,
                name: option.name,
                isCustom: true,
                isConnected: custom.isEnabled && !custom.models.isEmpty
            )
        }
        // Server catalog rows have no native enable flag — the switch state
        // lives in ProviderEnablementStore (user directive: one switch
        // everywhere, no status dots).
        if !includeDisabled {
            options = options.filter { option in
                option.isCustom || !ProviderEnablementStore.isDisabled(option.id, defaults: defaults)
            }
        }
        // Local providers (Ollama/OpenCode/MiMo CLI) — plan Раздел 1.
        options += LocalProviderLogic.providerOptions(
            from: LocalProviderLogic.load(),
            includeDisabled: includeDisabled
        )
        // Connected web providers (only after cookies captured) — plan Раздел 13 п.4.
        options += WebProviderConnectivity.providerOptions(
            WebProviderStore.load(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ).filter { includeDisabled || !ProviderEnablementStore.isDisabled($0.id, defaults: defaults) }
        return options
    }

    /// Whether a provider row is switched on. Custom and local providers keep
    /// their own flag; server catalog and web rows use the shared store.
    func isProviderEnabled(_ providerID: String) -> Bool {
        if let custom = customProviders.first(where: { $0.id == providerID }) {
            return custom.isEnabled
        }
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID }) {
            return local.isEnabled
        }
        return !ProviderEnablementStore.isDisabled(providerID, defaults: defaults)
    }

    /// Switch a provider row on/off. The selected provider is dropped when it
    /// is switched off so the composer never keeps a dead provider.
    func setProviderEnabled(_ providerID: String, isEnabled: Bool) {
        if customProviders.contains(where: { $0.id == providerID }) {
            setCustomProviderEnabled(providerID, isEnabled: isEnabled)
            return
        }
        if LocalProviderLogic.load(defaults: defaults).contains(where: { $0.id == providerID }) {
            LocalProviderLogic.setEnabled(id: providerID, isEnabled: isEnabled, defaults: defaults)
        } else {
            ProviderEnablementStore.setDisabled(
                !isEnabled,
                providerID: providerID,
                defaults: defaults
            )
        }
        if !isEnabled, selectedProviderID == providerID {
            selectProvider("")
        }
        validateAndReconcileSelections()
    }

    /// Whether a model is switched on. Always derived from the persisted
    /// disable list — a view never keeps its own copy, which is what made the
    /// old row refresh only after the selection moved to another model.
    func isModelEnabled(providerID: String, modelID: String) -> Bool {
        !DisabledModelStore.isDisabled(
            providerID: providerID,
            modelID: modelID,
            defaults: defaults
        )
    }

    /// The only path that flips a model switch. Persists the flag, publishes
    /// the catalog revision so the row, the composer and the model menu change
    /// in the same pass, and keeps the selection valid when the model that was
    /// selected is the one being switched off.
    func setModelEnabled(providerID: String, modelID: String, isEnabled: Bool) {
        guard isModelEnabled(providerID: providerID, modelID: modelID) != isEnabled else { return }
        DisabledModelStore.setDisabled(
            !isEnabled,
            providerID: providerID,
            modelID: modelID,
            defaults: defaults
        )
        // A model leaving the catalog is a catalog change: the same revision
        // the provider list already uses, so no view needs its own counter.
        providerCatalogRevision &+= 1
        guard !isEnabled else { return }
        reconcileSelectionAfterModelDisabled(providerID: providerID, modelID: modelID)
    }

    private func reconcileSelectionAfterModelDisabled(providerID: String, modelID: String) {
        guard selectedProviderID == providerID, selectedModel == modelID else { return }
        if let replacement = modelsForSelectedProvider.first {
            // Keep the stored preference: when the model is switched back on it
            // may be restored explicitly, but nothing dead stays selected now.
            selectModel(replacement, persistPreference: false)
        } else {
            selectedModel = ""
            defaults.set("", forKey: "com.mycoder.selectedModel")
        }
    }

    /// Effective selected model — for web providers resolve from their config
    /// since AppState.selectedModel is empty for web providers.
    func effectiveSelectedModel() -> String {
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let cfg = WebProviderStore.load().first(where: { $0.id == webID }) {
            return WebProviderSelectionLogic.effectiveSelectedModel(for: cfg)
        }
        return selectedModel
    }

    var modelsForSelectedProvider: [String] {
        // Web provider selected → its real (discovered) models (plan Раздел 13 п.4).
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let cfg = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            return WebProviderConnectivity.models(for: cfg)
        }
        // Local provider selected → its loaded models.
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == selectedProviderID }) {
            return local.models.filter {
                !DisabledModelStore.isDisabled(
                    providerID: local.id,
                    modelID: $0,
                    defaults: defaults
                )
            }
        }
        return ProviderSettingsLogic.models(
            for: selectedProviderID,
            in: serverProviders,
            customProviders: customProviders
        ).filter {
            !DisabledModelStore.isDisabled(
                providerID: selectedProviderID,
                modelID: $0,
                defaults: defaults
            )
        }
    }

    var selectedWebProviderConfig: WebProviderConfig? {
        guard let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) else { return nil }
        return WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID })
    }

    var availableWebEffortsForSelectedProvider: [WebEffort] {
        guard let config = selectedWebProviderConfig else { return [] }
        return WebProviderSelectionLogic.availableEfforts(
            for: config,
            modelID: effectiveSelectedModel()
        )
    }

    var selectedWebEffort: WebEffort? {
        guard let config = selectedWebProviderConfig else { return nil }
        return WebSelectionReconciliationLogic.effortForModel(
            config: config,
            modelID: effectiveSelectedModel(),
            availableEfforts: availableWebEffortsForSelectedProvider
        )
    }

    private func updateWebProvider(_ configID: String,
                                   modelID: String? = nil,
                                   effort: WebEffort? = nil) {
        var providers = WebProviderStore.load(defaults: defaults)
        guard let index = providers.firstIndex(where: { $0.id == configID }) else { return }
        if let modelID {
            providers[index] = WebProviderSelectionLogic.selectingModel(
                modelID,
                in: providers[index],
                availableModels: WebProviderConnectivity.models(for: providers[index])
            )
        }
        if let effort {
            providers[index] = WebProviderSelectionLogic.selectingEffort(effort, in: providers[index])
        }
        WebProviderStore.save(providers, defaults: defaults)
    }

    func selectWebEffort(_ effort: WebEffort) {
        guard let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
              availableWebEffortsForSelectedProvider.contains(effort) else { return }
        updateWebProvider(webID, effort: effort)
        if let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            Task { @MainActor in
                self.recordWebBrowserAction(action: "effort_selected",
                                            config: config,
                                            modelID: config.selectedModel,
                                            effort: effort,
                                            detail: "Composer effort selection")
            }
        }
        objectWillChange.send()
    }

    var supportsToolcallForSelection: Bool {
        ProviderCapabilityGates.canUseTools(
            modelID: effectiveSelectedModel(),
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            providers: serverProviders,
            customProviders: customProviders
        )
    }

    /// The provider the user explicitly picked; survives fallbacks while the
    /// provider is offline and is restored once it reappears.
    var preferredProviderID: String {
        defaults.string(forKey: "com.mycoder.preferredProviderID")
            ?? defaults.string(forKey: "com.mycoder.selectedProviderID")
            ?? ""
    }

    var preferredModelID: String {
        defaults.string(forKey: "com.mycoder.preferredModelID")
            ?? defaults.string(forKey: "com.mycoder.selectedModel")
            ?? ""
    }

    func selectProvider(_ providerID: String, persistPreference: Bool = true) {
        defer { persistSelectionToSelectedSession() }
        selectedProviderID = providerID
        providerConnectivity[providerID] = false
        Task { await refreshProviderConnectivity(providerID) }
        defaults.set(providerID, forKey: "com.mycoder.selectedProviderID")
        if persistPreference {
            defaults.set(providerID, forKey: "com.mycoder.preferredProviderID")
        }

        // Web providers are persisted locally rather than returned by
        // `mimo serve`, so ProviderSelectionLogic cannot resolve their models.
        // Select their discovered model (or the clearly-labelled pre-discovery
        // fallback) directly instead of leaving the chat with an empty model.
        if let webID = WebProviderConnectivity.configID(fromOptionID: providerID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            let models = WebProviderConnectivity.models(for: config)
            let preferred = WebSelectionReconciliationLogic.modelForRestore(
                config: config,
                globalPreferredModel: selectedModel,
                availableModels: models
            )
            selectedModel = preferred
            defaults.set(preferred, forKey: "com.mycoder.selectedModel")
            selectedVariant = ""
            updateWebProvider(webID, modelID: preferred)
            return
        }

        // Local providers carry their own model lists (persisted at
        // detect/refresh time) — the server+custom cascade below knows
        // nothing about them and would blank the model. Resolve from the
        // local list instead, then refresh it in the background so a stale
        // single-model list (e.g. from before credentials existed) heals.
        let localConfig = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID })
        if let local = localConfig {
            let resolved = LocalModelRefreshLogic.reconcile(current: selectedModel, fresh: local.models)
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            Task { await self.refreshLocalModels(providerID) }
        } else {
            let result = ProviderSelectionLogic.cascade(
                to: providerID,
                currentModelID: selectedModel,
                currentVariant: selectedVariant.isEmpty ? nil : selectedVariant,
                serverProviders: serverProviders,
                customProviders: customProviders
            )
            selectedModel = result.modelID
            defaults.set(result.modelID, forKey: "com.mycoder.selectedModel")
            selectedVariant = result.variant ?? ""
        }

        // Local providers carry their own model lists (persisted at
        // detect/refresh time) — the server+custom cascade above knows
        // nothing about them and would blank the model. Resolve from the
        // local list instead, then refresh it in the background so a stale
        // single-model list (e.g. from before credentials existed) heals.
        if let local = LocalProviderLogic.load(defaults: defaults).first(where: { $0.id == providerID }) {
            let resolved = LocalModelRefreshLogic.reconcile(current: selectedModel, fresh: local.models)
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            Task { await self.refreshLocalModels(providerID) }
        }

        if agentMode == .plan,
           !ProviderCapabilityGates.canSelectPlanAgent(
               modelID: effectiveSelectedModel(),
               providerID: providerID,
               providers: serverProviders,
               customProviders: customProviders
           ) {
            agentMode = .build
            Task { @MainActor in
                self.notificationService.info(
                    title: L.t(AppLocalizationKey.locModeSwitched),
                    message: L.t(AppLocalizationKey.locPlanNotSupported)
                )
            }
        }
    }

    @MainActor
    private func refreshProviderConnectivity(_ providerID: String) async {
        guard !providerID.isEmpty else { return }
        // A row the user switched off is never probed — it stays "offline".
        if ProviderEnablementStore.isDisabled(providerID, defaults: defaults) {
            providerConnectivity[providerID] = false
            return
        }
        if serverConnected && serverProviders.contains(where: { $0.id == providerID }) {
            providerConnectivity[providerID] = true
            return
        }
        if let webID = WebProviderConnectivity.configID(fromOptionID: providerID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            providerConnectivity[providerID] = WebProviderConnectivity.isConnected(
                config,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            return
        }
        if let local = LocalProviderLogic.load().first(where: { $0.id == providerID && $0.isEnabled }) {
            providerConnectivity[providerID] = await probeProviderURL(local.healthURL, headers: local.authHeaders())
            return
        }
        if let custom = customProviders.first(where: { $0.id == providerID && $0.isEnabled }) {
            let base = custom.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            providerConnectivity[providerID] = await probeProviderURL("\(base)/models")
            return
        }
        providerConnectivity[providerID] = false
    }

    private func probeProviderURL(_ string: String, headers: [String: String] = [:]) async -> Bool {
        guard let url = URL(string: string) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return (200..<500).contains(status)
        } catch {
            return false
        }
    }

    func selectModel(_ modelID: String, persistPreference: Bool = true) {
        defer { persistSelectionToSelectedSession() }
        if modelID.isEmpty {
            selectedModel = ""
            defaults.set("", forKey: "com.mycoder.selectedModel")
            if persistPreference {
                defaults.set("", forKey: "com.mycoder.preferredModelID")
            }
            return
        }
        guard modelsForSelectedProvider.contains(modelID) else { return }
        selectedModel = modelID
        defaults.set(modelID, forKey: "com.mycoder.selectedModel")
        if persistPreference {
            defaults.set(modelID, forKey: "com.mycoder.preferredModelID")
        }
        // Audit 2026-09-06: for a WEB provider the model lives in the web
        // config, not in `selectedModel`. Without this, the API/UI selection
        // never reached WebChatDriver and sends fell back to a stale model.
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) {
            var configs = WebProviderStore.load()
            if let idx = configs.firstIndex(where: { $0.id == webID }) {
                let updated = WebProviderSelectionLogic.selectingModel(modelID, in: configs[idx])
                if updated != configs[idx] {
                    configs[idx] = updated
                    WebProviderStore.save(configs)
                }
            }
        }
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID) {
            updateWebProvider(webID, modelID: modelID)
            if let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
                Task { @MainActor in
                    self.recordWebBrowserAction(action: "model_selected",
                                                config: config,
                                                modelID: modelID,
                                                effort: self.selectedWebEffort,
                                                detail: "Composer model selection")
                }
            }
            selectedVariant = ""
            return
        }
        selectedVariant = ProviderSettingsLogic.normalizedVariant(
            selectedVariant.isEmpty ? nil : selectedVariant,
            for: modelID,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        ) ?? ""
    }

    /// Store the current provider/model on the open chat so reopening it
    /// restores the same selection.
    private func persistSelectionToSelectedSession() {
        guard let sessionID = selectedSession?.id else { return }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].modelID = selectedModel
            sessions[index].providerID = selectedProviderID
        }
        DatabaseBridge.shared.setSessionModel(
            sessionId: sessionID,
            modelID: selectedModel,
            providerID: selectedProviderID
        )
    }

    /// Restore the provider/model a chat used last. Chats without their own
    /// selection fall back to the last selection made outside any chat.
    private func restoreSelection(for session: ChatSession) {
        let selection = SessionModelSelectionLogic.resolve(
            sessionProviderID: session.providerID,
            sessionModelID: session.modelID,
            preferredProviderID: defaults.string(forKey: "com.mycoder.preferredProviderID"),
            preferredModelID: defaults.string(forKey: "com.mycoder.preferredModelID")
        )
        guard !selection.providerID.isEmpty else { return }
        if selection.providerID != selectedProviderID {
            selectProvider(selection.providerID, persistPreference: false)
        }
        guard let modelID = SessionModelSelectionLogic.applyableModel(
            selection.modelID,
            availableModels: modelsForSelectedProvider
        ) else { return }
        if modelID != selectedModel {
            selectModel(modelID, persistPreference: false)
        }
    }

    func validateAndReconcileSelections() {
        let rawOptions = rawProviderOptions(includeDisabled: false)
        let canonicalID = ProviderDuplicationLogic.canonicalID(
            for: selectedProviderID,
            in: rawOptions
        )
        if canonicalID != selectedProviderID {
            selectProvider(canonicalID, persistPreference: false)
        }

        let options = ProviderDuplicationLogic.deduplicatedOptions(rawOptions)
        if options.isEmpty {
            // Only an enabled server row may be picked as a fallback — a row
            // the user switched off must never become the active provider.
            if selectedProviderID.isEmpty,
               let firstServer = serverProviders.first(where: {
                   !ProviderEnablementStore.isDisabled($0.id, defaults: defaults)
               }) {
                selectProvider(firstServer.id, persistPreference: false)
            }
            return
        }

        // Restore the user's explicit choice as soon as it is available again.
        if let restored = SelectionRestoreLogic.resolvedProviderID(
            preferred: preferredProviderID,
            current: selectedProviderID,
            options: options.map(\.id)
        ) {
            selectProvider(restored, persistPreference: false)
            restorePreferredModelIfAvailable()
            return
        }

        if selectedProviderID.isEmpty || !options.contains(where: { $0.id == selectedProviderID }) {
            // Temporary fallback — must not overwrite the stored preference.
            selectProvider(options[0].id, persistPreference: false)
            return
        }

        restorePreferredModelIfAvailable()

        let result = ProviderSelectionLogic.cascade(
            to: selectedProviderID,
            currentModelID: selectedModel,
            currentVariant: selectedVariant.isEmpty ? nil : selectedVariant,
            serverProviders: serverProviders,
            customProviders: customProviders
        )
        selectedModel = result.modelID
        defaults.set(result.modelID, forKey: "com.mycoder.selectedModel")
        selectedVariant = result.variant ?? ""
    }

    private func restorePreferredModelIfAvailable() {
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            let resolved = WebSelectionReconciliationLogic.modelForRestore(
                config: config,
                globalPreferredModel: preferredModelID,
                availableModels: WebProviderConnectivity.models(for: config)
            )
            var providers = WebProviderStore.load(defaults: defaults)
            if let index = providers.firstIndex(where: { $0.id == webID }),
               providers[index].selectedModel != resolved {
                providers[index].selectedModel = resolved
                WebProviderStore.save(providers, defaults: defaults)
            }
            selectedModel = resolved
            defaults.set(resolved, forKey: "com.mycoder.selectedModel")
            return
        }
        if let restoredModel = SelectionRestoreLogic.resolvedModelID(
            preferred: preferredModelID,
            current: selectedModel,
            options: modelsForSelectedProvider
        ) {
            selectModel(restoredModel, persistPreference: false)
        }
    }

    var availableVariantsForSelectedModel: [String] {
        ProviderSettingsLogic.availableVariants(
            for: selectedModel,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        )
    }

    var supportsReasoningForSelectedModel: Bool {
        ProviderSettingsLogic.supportsReasoning(
            for: selectedModel,
            in: serverProviders,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
            customProviders: customProviders
        )
    }

    /// Whether the currently selected provider is an ACP-enabled custom provider.
    var isSelectedACPProvider: Bool {
        guard let custom = customProviders.first(where: { $0.id == selectedProviderID }) else {
            return false
        }
        return custom.type == .acp && custom.acpEnabled
    }

    /// Whether the currently selected provider is a browser web provider.
    /// Used to hide non-web controls (variant/effort menus) from the
    /// composer — web effort is discovered with each model and injected
    /// by the driver, never hand-picked (user directive 2026-09-06).
    var isSelectedWebProvider: Bool {
        WebProviderConnectivity.configID(fromOptionID: selectedProviderID) != nil
    }

    /// Returns an `ACPClient` for the currently selected ACP provider, or nil.
    var acpClient: ACPClient? {
        guard isSelectedACPProvider,
              let custom = customProviders.first(where: { $0.id == selectedProviderID }),
              let url = URL(string: custom.baseURL) else {
            return nil
        }
        let key = custom.apiKey
        return ACPClient(baseURL: url, apiKey: key)
    }

    func applySendSelections(_ selections: SessionSendSelections) {
        if let agentMode = selections.agentMode {
            self.agentMode = agentMode
        }
        if let providerID = selections.providerID, !providerID.isEmpty {
            if providerOptions.contains(where: { $0.id == providerID }) {
                selectProvider(providerID)
            }
        }
        if let modelID = selections.modelID, !modelID.isEmpty {
            if modelsForSelectedProvider.contains(modelID) {
                selectModel(modelID)
            } else if providerOptions.contains(where: { $0.id == selections.providerID ?? selectedProviderID }) {
                selectModel(modelID)
            }
        }
        if let variant = selections.variant, !variant.isEmpty {
            selectedVariant = ProviderSettingsLogic.normalizedVariant(
                variant,
                for: selectedModel,
                in: serverProviders,
                providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
                customProviders: customProviders
            ) ?? variant
        }
        if agentMode == .plan,
           !ProviderCapabilityGates.canSelectPlanAgent(
               modelID: selectedModel,
               providerID: selectedProviderID.isEmpty ? nil : selectedProviderID,
               providers: serverProviders,
               customProviders: customProviders
           ) {
            agentMode = .build
        }
    }

    func applyAccessLevelToServer() async {
        guard serverConnected else { return }
        let patch: [String: Any] = [
            "permission": AccessLevelPermissionLogic.permissionPatch(for: accessLevel)
        ]
        do {
            _ = try await mimoClient.updateGlobalConfig(patch)
        } catch {
            print("Failed to update permission config: \(error)")
        }
    }

    func syncAccessLevelFromServer() async {
        do {
            let config = try await mimoClient.globalConfig()
            let mapped = AccessLevelPermissionLogic.accessLevel(from: config.permission?.asDictionary)
            await MainActor.run {
                isSyncingAccessLevel = true
                self.accessLevel = mapped
                isSyncingAccessLevel = false
            }
        } catch {
            print("Failed to sync access level: \(error)")
        }
    }
    
    func navigateBack() {
        navigationLock.lock()
        guard navigationIndex > 0 else {
            navigationLock.unlock()
            return
        }
        navigationIndex -= 1
        let ws = navigationHistory[navigationIndex]
        isNavigatingHistory = true
        navigationLock.unlock()
        selectWorkspace(ws)
        navigationLock.lock()
        isNavigatingHistory = false
        navigationLock.unlock()
    }

    func navigateForward() {
        navigationLock.lock()
        guard navigationIndex < navigationHistory.count - 1 else {
            navigationLock.unlock()
            return
        }
        navigationIndex += 1
        let ws = navigationHistory[navigationIndex]
        isNavigatingHistory = true
        navigationLock.unlock()
        selectWorkspace(ws)
        navigationLock.lock()
        isNavigatingHistory = false
        navigationLock.unlock()
    }

    var canNavigateBack: Bool {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        return navigationIndex > 0 && navigationIndex < navigationHistory.count
    }

    var canNavigateForward: Bool {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        return navigationIndex < navigationHistory.count - 1 && navigationIndex >= 0 && navigationHistory.count > 0
    }
    
    func setCustomProviderEnabled(_ providerID: String, isEnabled: Bool) {
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        customProviders[index].isEnabled = isEnabled
        saveCustomProviders()
        if isEnabled {
            loadModelsFromCustomProvider(customProviders[index])
        }
        validateAndReconcileSelections()
    }

    func addCustomProvider(_ provider: CustomProvider) {
        // Save API key to Keychain and clear plain storage before saving to UserDefaults
        if !provider.apiKey.isEmpty {
            DatabaseBridge.shared.saveProviderAPIKey(providerId: provider.id, apiKey: provider.apiKey)
        }
        var cleanProvider = provider
        // In-memory copy keeps the working key (restored from Keychain) so
        // send-readiness validation sees the truth — the plain-key strip only
        // matters for the UserDefaults serialization below. Without this, a
        // freshly added/edited provider blocks sending with "requires an API
        // key" until the app restarts (audit ARCH-04).
        cleanProvider.apiKey = provider.apiKey.isEmpty
            ? (DatabaseBridge.shared.getProviderAPIKey(providerId: provider.id) ?? "")
            : provider.apiKey
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = cleanProvider
        } else {
            customProviders.append(cleanProvider)
        }
        saveCustomProviders()
        if provider.isEnabled {
            loadModelsFromCustomProvider(provider)
        }
    }
    
    func removeCustomProvider(_ provider: CustomProvider) {
        DatabaseBridge.shared.deleteProviderAPIKey(providerId: provider.id)
        ProviderEnablementStore.clear(providerID: provider.id, defaults: defaults)
        customProviders.removeAll { $0.id == provider.id }
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    func updateCustomProvider(_ updated: CustomProvider) {
        guard let index = customProviders.firstIndex(where: { $0.id == updated.id }) else { return }
        // Save API key to Keychain and clear plain storage
        if !updated.apiKey.isEmpty {
            DatabaseBridge.shared.saveProviderAPIKey(providerId: updated.id, apiKey: updated.apiKey)
        }
        var cleanProvider = updated
        // Same ARCH-04 fix as addCustomProvider: the in-memory copy must
        // reflect the Keychain-resident key so readiness checks pass and the
        // OpenAI-compatible send route can resolve it without a restart.
        cleanProvider.apiKey = updated.apiKey.isEmpty
            ? (DatabaseBridge.shared.getProviderAPIKey(providerId: updated.id) ?? "")
            : updated.apiKey
        customProviders[index] = cleanProvider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    /// Rename a custom provider's model in place. The new id becomes a manual
    /// entry and the old one is hidden, so a catalog refresh merges cleanly
    /// instead of reverting the rename to the server-side list.
    func renameCustomModel(providerID: String, modelID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != modelID else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        provider.customModels.removeAll { $0 == modelID }
        if !provider.hiddenModels.contains(modelID) {
            provider.hiddenModels.append(modelID)
        }
        if !provider.customModels.contains(trimmed) {
            provider.customModels.append(trimmed)
        }
        provider.models = provider.models.map { $0 == modelID ? trimmed : $0 }
        if !provider.models.contains(trimmed) {
            provider.models.append(trimmed)
        }
        customProviders[index] = provider
        saveCustomProviders()
        if selectedProviderID == providerID && selectedModel == modelID {
            selectedModel = trimmed
            defaults.set(trimmed, forKey: "com.mycoder.selectedModel")
            defaults.set(trimmed, forKey: "com.mycoder.preferredModelID")
        }
        validateAndReconcileSelections()
    }

    /// Clone a model entry under a new id (manual entry, survives refresh).
    func cloneCustomModel(providerID: String, modelID: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != modelID else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        guard !provider.models.contains(trimmed) else { return }
        provider.customModels.append(trimmed)
        provider.hiddenModels.removeAll { $0 == trimmed }
        provider.models.append(trimmed)
        customProviders[index] = provider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    /// Add a fully custom model id that the provider's catalog may not list.
    func addCustomModel(providerID: String, modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        var provider = customProviders[index]
        guard !provider.models.contains(trimmed) else { return }
        provider.customModels.append(trimmed)
        provider.hiddenModels.removeAll { $0 == trimmed }
        provider.models.append(trimmed)
        customProviders[index] = provider
        saveCustomProviders()
        validateAndReconcileSelections()
    }

    func testProvider(url: String, apiKey: String, type: ProviderType) async -> Bool {
        guard let modelsURLString = ProviderEndpointLogic.modelsURL(for: url),
              let testURL = URL(string: modelsURLString) else { return false }
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 10
        
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return ProviderConnectionValidationLogic.isValidModelsResponse(statusCode: http.statusCode, body: data)
        } catch {
            return false
        }
    }
    
    func refreshModels(for providerID: String) {
        guard let provider = customProviders.first(where: { $0.id == providerID }) else { return }
        loadModelsFromCustomProvider(provider)
    }

    /// Background refresh of a local provider's model list (fetch → persist →
    /// reconcile selection). Never wipes: failed/empty fetch keeps everything
    /// as-is with an honest status message. `fetch` is injectable for tests.
    /// All state mutations hop to MainActor: @Published writes from a
    /// background task abort the app via AppKit menu assertions (crash
    /// 2026-10-15, `providerModelLoadMessages.modify` off-main).
    func refreshLocalModels(
        _ providerID: String,
        fetch: @escaping (LocalProviderConfig) async -> [String]? = { await LocalProviderLogic.fetchModels(for: $0) }
    ) async {
        let locals = LocalProviderLogic.load(defaults: defaults)
        guard let config = locals.first(where: { $0.id == providerID && $0.isEnabled }) else { return }
        let fresh = await fetch(config)
        await MainActor.run {
            guard let fresh, !fresh.isEmpty else {
                self.providerModelLoadMessages[providerID] =
                    "Could not refresh models from \(config.serveBaseURL). Check the server and credentials; keeping existing list."
                return
            }
            var updated = LocalProviderLogic.load(defaults: self.defaults)
            if let idx = updated.firstIndex(where: { $0.id == providerID }) {
                updated[idx].models = fresh
                LocalProviderLogic.save(updated, defaults: self.defaults)
            }
            if self.selectedProviderID == providerID {
                let next = LocalModelRefreshLogic.reconcile(current: self.selectedModel, fresh: fresh)
                if next != self.selectedModel {
                    self.selectedModel = next
                    self.defaults.set(next, forKey: "com.mycoder.selectedModel")
                }
            }
            self.providerModelLoadMessages[providerID] = "Loaded \(fresh.count) model\(fresh.count == 1 ? "" : "s") from \(config.serveBaseURL)."
        }
    }

    func removeModel(_ modelID: String, from providerID: String) {
        guard let index = customProviders.firstIndex(where: { $0.id == providerID }) else { return }
        customProviders[index].models.removeAll { $0 == modelID }
        customProviders[index].customModels.removeAll { $0 == modelID }
        if !customProviders[index].hiddenModels.contains(modelID) {
            customProviders[index].hiddenModels.append(modelID)
        }
        saveCustomProviders()
        if selectedProviderID == providerID && selectedModel == modelID {
            selectedModel = customProviders[index].models.first ?? ""
            defaults.set(selectedModel, forKey: "com.mycoder.selectedModel")
            defaults.set(selectedModel, forKey: "com.mycoder.preferredModelID")
            selectedVariant = ""
        }
        validateAndReconcileSelections()
    }

    func providerModelLoadMessage(for providerID: String) -> String? {
        providerModelLoadMessages[providerID]
    }

    private func loadModelsFromCustomProvider(_ provider: CustomProvider) {
        // Custom providers are stored locally and merged into the picker only.
        // MiMo Serve reads provider credentials from mimocode.json on disk; this
        // app does not push custom provider config to the server API.
        Task {
            let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: trimmedBaseURL.hasSuffix("/models")
                                ? trimmedBaseURL
                                : "\(trimmedBaseURL)/models") else {
                await MainActor.run {
                    self.providerModelLoadMessages[provider.id] = "Invalid provider URL."
                }
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // Use Keychain-backed API key if available, fall back to plain storage
            let apiKey = provider.getSecureAPIKey() ?? ""
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "Model request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)): \(String(body.prefix(180)))"
                    }
                    return
                }
                guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "The provider returned an invalid model-list response."
                    }
                    return
                }
                // OpenAI-compatible: { data: [{ id }] }; Ollama: { models:
                // [{ name }] }; Google: { models: [{ name: "models/..." }] }.
                // Keep refresh and Test Connection on one canonical parser so
                // blank IDs, fallback names, and duplicate rows behave alike.
                let discoveredModels = ProviderConnectionValidationLogic.modelIDs(from: data)
                let models: [String] = provider.type == .openCodeZen
                    ? OpenCodeZenCatalog.availableModels(from: discoveredModels, apiKey: apiKey)
                    : discoveredModels
                guard !models.isEmpty else {
                    await MainActor.run {
                        self.providerModelLoadMessages[provider.id] = "No models were found in this provider's response. Check its API base URL."
                    }
                    return
                }
                let providerID = provider.id
                let loadedModels = models
                let modelCount = loadedModels.count
                let modelLoadMessage = provider.type == .openCodeZen
                    ? "Loaded \(modelCount) OpenCode Zen model\(modelCount == 1 ? "" : "s") · \(OpenCodeZenCatalog.accessSummary(hasAPIKey: !apiKey.isEmpty))"
                    : "Loaded \(modelCount) model\(modelCount == 1 ? "" : "s")."
                await MainActor.run { [providerID, loadedModels, modelLoadMessage] in
                    if let index = customProviders.firstIndex(where: { $0.id == providerID }) {
                        customProviders[index].models = CustomModelListLogic.mergedModels(
                            provider: customProviders[index],
                            discovered: loadedModels
                        )
                        saveCustomProviders()
                    }
                    providerModelLoadMessages[providerID] = modelLoadMessage
                    if selectedProviderID == providerID || selectedProviderID.isEmpty {
                        validateAndReconcileSelections()
                    }
                }
            } catch {
                await MainActor.run {
                    self.providerModelLoadMessages[provider.id] = "Could not load models: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func saveCustomProviders() {
        // Strip apiKey fields before saving to UserDefaults — keys live in Keychain
        let cleanProviders = customProviders.map { provider -> CustomProvider in
            var clean = provider
            clean.apiKey = ""
            return clean
        }
        if let data = try? JSONEncoder().encode(cleanProviders) {
            defaults.set(data, forKey: "com.mycoder.customProviders")
        }
        NotificationCenter.default.post(name: .providersChanged, object: nil)
    }
    
    /// Current session goal, shown in the TopBar (plan Раздел 5 Блок 1 п.9).
    #if canImport(WebKit)
    /// Lazy browser pool. Each project/chat/provider gets an isolated page;
    /// cookies remain shared through WKWebView's default data store. We never
    /// create 100 pages up front: the cap is a safety ceiling, not a target.
    private var webViews: [String: WKWebView] = [:]
    private var webViewLastUsed: [String: Date] = [:]
    /// Structured pool keys parallel to `webViews` (storage keys join fields
    /// with "::", which can theoretically collide with path characters).
    private var webViewKeys: [String: WebBrowserInstanceKey] = [:]
    private let maxWebBrowserInstances = 100
    /// Round 30: permissive navigation/UI policies kept alive per webview so
    /// vendor region redirects (kimi.com → kimi.ai), window.open hops and JS
    /// dialogs all work in the embedded browser.
    private var webNavigationPolicies: [String: PermissiveWebNavigationPolicy] = [:]

    @Published private(set) var webBrowserActionJournal: [WebBrowserActionRecord] = WebBrowserActionJournal.load()

    /// User directive 2026-09-09: the web provider's live browser page must be
    /// VISIBLE inside the chat as a mini-preview while a web provider is
    /// selected — no hidden offscreen window. The panel re-parents the SAME
    /// pooled WKWebView (never recreates it) so login state, the conversation
    /// and in-flight streams survive across requests; switching chats moves
    /// the panel by updating its key, exactly like opening another tab of the
    /// same site. Non-web providers leave the panel untouched (it keeps
    /// showing the last web provider's page).
    @Published var webBrowserPanelConfig: WebBrowserPanelConfig?

    /// Ensure the provider's page exists in the pool and surface it in the
    /// visible mini-browser panel. Call when a WEB provider turn starts.
    @MainActor
    func showWebBrowserPanel(for config: WebProviderConfig,
                             projectID: String,
                             chatID: String) {
        _ = webView(for: config, projectID: projectID, chatID: chatID)
        webBrowserPanelConfig = WebBrowserPanelConfig(
            providerID: config.id,
            providerName: config.displayName,
            projectID: projectID,
            chatID: chatID
        )
    }

    /// Detach the webview from the visible panel back to the hidden host
    /// window WITHOUT destroying it — the page keeps its state (cookies,
    /// conversation, stream) for the next web turn.
    @MainActor
    func hideWebBrowserPanel() {
        webBrowserPanelConfig = nil
    }

    /// User directive 2026-09-09: switching to another chat/project surfaces
    /// THAT chat's pooled webview ("another tab of the same site") when one
    /// exists; otherwise the panel keeps showing whatever it showed (it is
    /// never hidden or destroyed by navigation alone).
    @MainActor
    func showPanelForChatIfPooled(projectID: String, chatID: String) {
        let candidates = webViewKeys.values.filter {
            $0.projectID == projectID && $0.chatID == chatID
        }
        guard !candidates.isEmpty else { return }
        let best = candidates.max {
            (webViewLastUsed[$0.storageKey] ?? .distantPast)
                < (webViewLastUsed[$1.storageKey] ?? .distantPast)
        } ?? candidates[0]
        let name = WebProviderStore.load(defaults: defaults)
            .first(where: { $0.id == best.providerID })?.displayName ?? best.providerID
        webBrowserPanelConfig = WebBrowserPanelConfig(
            providerID: best.providerID,
            providerName: name,
            projectID: projectID,
            chatID: chatID
        )
    }

    @MainActor
    func webView(for config: WebProviderConfig,
                 projectID: String? = nil,
                 chatID: String? = nil) -> WKWebView {
        let instanceKey = WebBrowserInstanceKey(
            projectID: projectID ?? selectedWorkspace?.id ?? "global",
            chatID: chatID ?? selectedSession?.id ?? "provider-default",
            providerID: config.id,
            activeSessionID: config.activeSessionID ?? WebSessionManager.defaultSessionID
        )
        let key = instanceKey.storageKey
        if let existing = webViews[key] {
            webViewLastUsed[key] = Date()
            return existing
        }
        // Evict the policy together with its webview.
        if webViews.count >= maxWebBrowserInstances,
           let evictKey = webViewLastUsed.min(by: { $0.value < $1.value })?.key,
           let evicted = webViews.removeValue(forKey: evictKey) {
            evicted.stopLoading()
            evicted.removeFromSuperview()
            webViewLastUsed.removeValue(forKey: evictKey)
            _ = webNavigationPolicies.removeValue(forKey: evictKey)
            _ = webViewKeys.removeValue(forKey: evictKey)
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        // UX audit 2026-09-06: WebKit's default shows an I-beam text cursor
        // over vendor links/buttons that only contain text ("Войти" etc.) —
        // users read it as non-clickable. Force the pointing-hand cursor on
        // every interactive element, like a real browser does.
        config.userContentController.addUserScript(WKUserScript(
            source: """
            (function(){
              var style = document.createElement('style');
              style.textContent = [
                'a, button, [role="button"], [role="option"], [role="menuitem"],',
                '[onclick], input[type="button"], input[type="submit"], input[type="checkbox"],',
                'label[for], summary, [class*="btn"], [class*="button"], [class*="clickable"]',
                '{ cursor: pointer !important; }'
              ].join(' ');
              (document.head || document.documentElement).appendChild(style);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        // Round 30: maximally permissive navigation — allow every host/scheme,
        // redirect popups into the same view, auto-answer JS dialogs.
        let policy = PermissiveWebNavigationPolicy(ownerWebView: wv)
        wv.navigationDelegate = policy
        wv.uiDelegate = policy
        webNavigationPolicies[key] = policy
        // Add to a hidden window to ensure proper loading
        let hiddenWindow = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: 1280, height: 720),
                                    styleMask: [.borderless],
                                    backing: .buffered,
                                    defer: false)
        hiddenWindow.contentView = wv
        hiddenWindow.orderFront(nil)
        hiddenWindow.alphaValue = 1.0
        webViews[key] = wv
        webViewKeys[key] = instanceKey
        webViewLastUsed[key] = Date()
        return wv
    }

    /// Evaluate JavaScript on the most recently used webview (debug endpoint).
    @MainActor
    func debugEvaluateJS(_ script: String, webviewKey: String? = nil) async -> Any? {
        // Explicit target key wins (debug API routing to a specific webview).
        if let webviewKey, let wv = webViews[webviewKey] {
            return await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
                wv.evaluateJavaScript(script) { result, error in
                    if let error {
                        continuation.resume(returning: "ERROR: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
        }
        // Try the most recent webview first
        if let lastUsed = webViewLastUsed.max(by: { $0.value < $1.value }),
           let wv = webViews[lastUsed.key] {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
                wv.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        continuation.resume(returning: "ERROR: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
            if let str = result as? String, str.hasPrefix("ERROR:") {
                // Try other webviews
            } else if result != nil {
                return result
            }
        }
        // Fallback: try all webviews
        for (_, wv) in webViews {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
                wv.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        continuation.resume(returning: "ERROR: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
            if let str = result as? String, str.hasPrefix("ERROR:") {
                continue
            } else if result != nil {
                return result
            }
        }
        return nil
    }

    /// Get all webview URLs for debugging.
    @MainActor
    func debugWebviewURLs() -> [String: String] {
        var urls: [String: String] = [:]
        for (key, wv) in webViews {
            urls[key] = wv.url?.absoluteString ?? "no-url"
        }
        return urls
    }

    @MainActor
    func recordWebBrowserAction(action: String,
                                config: WebProviderConfig,
                                projectID: String? = nil,
                                chatID: String? = nil,
                                modelID: String? = nil,
                                effort: WebEffort? = nil,
                                remoteChatID: String? = nil,
                                detail: String? = nil) {
        let record = WebBrowserActionRecord(
            action: action,
            projectID: projectID ?? selectedWorkspace?.id ?? "global",
            chatID: chatID ?? selectedSession?.id ?? "unknown-chat",
            providerID: config.id,
            providerName: config.displayName,
            modelID: modelID ?? config.selectedModel,
            effort: effort,
            remoteChatID: remoteChatID,
            detail: detail
        )
        webBrowserActionJournal = WebBrowserActionJournal.append(record, defaults: defaults)
    }

    @MainActor
    func webRemoteChatKey(for config: WebProviderConfig,
                          projectID: String,
                          chatID: String) -> WebRemoteChatKey {
        WebRemoteChatKey(providerID: config.id,
                         activeSessionID: config.activeSessionID ?? WebSessionManager.defaultSessionID,
                         projectID: projectID,
                         localChatID: chatID)
    }

    @MainActor
    func webRemoteChatMapping(for config: WebProviderConfig,
                              projectID: String,
                              chatID: String) -> WebRemoteChatMapping? {
        WebRemoteChatStore.mapping(for: webRemoteChatKey(for: config, projectID: projectID, chatID: chatID),
                                   defaults: defaults)
    }

    @MainActor
    func saveWebRemoteChatMapping(_ mapping: WebRemoteChatMapping) {
        WebRemoteChatStore.upsert(mapping, defaults: defaults)
    }

    @MainActor
    func clearWebRemoteChats(providerID: String, activeSessionID: String? = nil) {
        WebRemoteChatStore.clear(providerID: providerID, activeSessionID: activeSessionID, defaults: defaults)
    }

    /// Stop the active browser generation for a provider. This is separate from
    /// cancelling the Swift task: the vendor page must receive its own stop
    /// action or it can keep consuming tokens in the background.
    @MainActor
    func stopWebGeneration(providerID: String,
                            projectID: String,
                            chatID: String) async {
        guard let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == providerID }) else { return }
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        let selectors = WebVendorSelectors(
            input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
            sendButton: catalogEntry?.sendButton ?? "button[type='submit']",
            responseContainer: catalogEntry?.responseContainer ?? "div[class*='message']",
            stopButton: catalogEntry?.stopButton ?? "button[aria-label*='stop' i], button[data-testid='stop-button']"
        )
        let bridge = WKWebViewBrowserBridge(
            webView: webView(for: config, projectID: projectID, chatID: chatID),
            selectors: selectors
        )
        try? await bridge.stopGeneration()
    }

    /// Refresh the *real* model list for an authenticated web provider. The
    /// login sheet uses a separate WKWebView, so this method first restores the
    /// captured cookies into the persistent chat web view, opens the vendor
    /// page, waits for its composer, then opens and reads the model dropdown.
    /// It returns an actionable message instead of silently leaving 0 models.
    @MainActor
    func refreshWebModels(for config: WebProviderConfig,
                          projectID: String? = nil,
                          chatID: String? = nil) async -> String {
        // Prefer the user-picked selector but always retain catalog fallbacks.
        // A stale custom selector must not hide the live model menu.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        let selector = [
            config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            catalogEntry?.modelDropdown ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        if selector.isEmpty {
            return L.t(AppLocalizationKey.locWebNoSelectorYet)
        }
        let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
        guard let store = WebSessionManager.restore(providerId: config.id,
                                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                    sessionID: sessionID),
              !store.cookies.isEmpty,
              !WebSessionManager.isExpired(store) else {
            return L.t(AppLocalizationKey.locWebLoginFirst)
        }

        let selectors = WebVendorSelectors(
            input: "textarea, div[contenteditable='true']",
            sendButton: "button[type='submit'], button[aria-label*='send'], button[data-testid='send-button']",
            responseContainer: "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: "button[aria-label*='stop'], button[data-testid='stop-button'], button[class*='stop']"
        )
        let bridge = WKWebViewBrowserBridge(webView: webView(for: config, projectID: projectID, chatID: chatID), selectors: selectors)
        var localStorageWarning: String?
        do {
            let payload = WebSessionRestorationLogic.payload(from: store)
            try await bridge.setCookies(payload.cookies)
            try await bridge.navigate(to: config.chatURL)
            do {
                try await bridge.setLocalStorage(payload.localStorage)
                if !payload.localStorage.isEmpty {
                    try await bridge.navigate(to: config.chatURL)
                }
            } catch {
                localStorageWarning = " (localStorage restore unavailable: \(error.localizedDescription))"
            }
            var inputFound = false
            for _ in 0..<30 {
                if try await bridge.exists(selector: selectors.input) {
                    inputFound = true
                    break
                }
                await bridge.wait(ms: 500)
            }
            guard inputFound else {
                return L.t(AppLocalizationKey.locWebInputNotFound)
            }
            // Login-wall gate: a logged-out vendor page can never yield
            // models — the old flow scraped login CTAs and sidebar chrome as
            // "models" (live ChatGPT evidence 2026-09-06). Report honestly.
            if await WebModelDiscovery.isLoginWall(using: bridge) {
                return "The \(config.displayName) page shows a login screen — open the provider login, sign in, then refresh models again."
            }
            let models = await WebModelDiscovery.discoverAllModels(using: bridge,
                                                                    dropdownSelector: selector,
                                                                    vendor: config.vendor)
            guard let found = models else {
                return String(format: L.t(AppLocalizationKey.locWebModelListFailed), config.displayName)
            }
            let capabilityModels = await WebModelDiscovery.discoverModelCapabilities(
                using: bridge,
                dropdownSelector: selector,
                vendor: config.vendor,
                models: found,
                effortDropdownSelector: config.effortDropdown ?? catalogEntry?.effortDropdown
            )
            let resolvedModels = capabilityModels.isEmpty ? found : capabilityModels
            let discoveredEfforts = Array(Set(resolvedModels.flatMap(\.availableEfforts))).sorted { $0.rawValue < $1.rawValue }
            if !config.selectedModel.isEmpty {
                let itemSelector = catalogEntry?.modelItem ?? "[role='option'], [class*='model'], li"
                var restored = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: config.selectedModel)) == true
                if !restored {
                    for selector in ["[role='option']", "[role='menuitem']", "[class*='model-item']"] {
                        if (try? await bridge.clickVisibleTextExact(selector: selector, text: config.selectedModel)) == true {
                            restored = true
                            break
                        }
                    }
                }
                if restored { await bridge.wait(ms: 250) }
            }
            var updated = WebModelRefreshLogic.replacing(config: config, with: resolvedModels)
            updated.discoveredEffortLevels = discoveredEfforts
            WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
            if resolvedModels.isEmpty {
                return String(format: L.t(AppLocalizationKey.locWebModelListFailed), config.displayName)
            }
            if selectedProviderID == "web:\(config.id)" {
                selectProvider(selectedProviderID, persistPreference: false)
            }
            let count = resolvedModels.count
            let plural = count == 1 ? "" : "s"
            // Audit 2026-09-06: the message MUST match what the composer
            // actually offers. allModels filters tier-gated entries
            // (isSelectable=false); reporting the raw discovered count made
            // the user see "loaded 10" while the card showed 3.
            let refreshedConfig = WebModelRefreshLogic.replacing(config: config, with: resolvedModels)
            let selectableCount = refreshedConfig.allModels.count
            let gatedCount = resolvedModels.filter { !$0.isSelectable }.count
            let baseMessage = String(format: L.t(AppLocalizationKey.locWebLoadedModels), selectableCount, plural, config.displayName)
            let gatedNote = gatedCount > 0
                ? " \(gatedCount) more require a higher plan (not selectable)."
                : ""
            return baseMessage + gatedNote + (localStorageWarning ?? "")
        } catch {
            return String(format: L.t(AppLocalizationKey.locWebRefreshFailed), error.localizedDescription)
        }
    }
    #endif
    /// Refresh available effort/thinking levels for a web provider by reading
    /// the effort dropdown on the provider's web page.
    /// Returns a status message describing the result.
    @MainActor
    func refreshWebEffort(for config: WebProviderConfig,
                          projectID: String? = nil,
                          chatID: String? = nil) async -> String {
        #if canImport(WebKit)
        guard let effortSelector = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)?.effortDropdown else {
            return L.t(AppLocalizationKey.locWebEffortNoSelector)
        }
        let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
        guard let store = WebSessionManager.restore(providerId: config.id,
                                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                    sessionID: sessionID),
              !store.cookies.isEmpty,
              !WebSessionManager.isExpired(store) else {
            return L.t(AppLocalizationKey.locWebEffortLoginFirst)
        }

        let selectors = WebVendorSelectors(
            input: "textarea, div[contenteditable='true']",
            sendButton: "button[type='submit'], button[aria-label*='send'], button[data-testid='send-button']",
            responseContainer: "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: "button[aria-label*='stop'], button[data-testid='stop-button'], button[class*='stop']"
        )
        let bridge = WKWebViewBrowserBridge(webView: webView(for: config, projectID: projectID, chatID: chatID), selectors: selectors)
        var localStorageWarning: String?
        do {
            let payload = WebSessionRestorationLogic.payload(from: store)
            try await bridge.setCookies(payload.cookies)
            try await bridge.navigate(to: config.chatURL)
            do {
                try await bridge.setLocalStorage(payload.localStorage)
                if !payload.localStorage.isEmpty {
                    try await bridge.navigate(to: config.chatURL)
                }
            } catch {
                localStorageWarning = " (localStorage restore unavailable: \(error.localizedDescription))"
            }
            var inputFound = false
            for _ in 0..<30 {
                if try await bridge.exists(selector: selectors.input) {
                    inputFound = true
                    break
                }
                await bridge.wait(ms: 500)
            }
            guard inputFound else {
                return L.t(AppLocalizationKey.locWebInputNotFound)
            }
            guard let efforts = await WebModelDiscovery.discoverEffort(using: bridge,
                                                                       effortDropdownSelector: effortSelector,
                                                                       vendor: config.vendor) else {
                return String(format: L.t(AppLocalizationKey.locWebEffortReadFailed), config.displayName)
            }
            var updated = config
            updated.effort = efforts.first ?? .medium
            updated.discoveredEffortLevels = efforts
            WebProviderStore.save(WebProviderStore.upsert(updated, in: WebProviderStore.load()))
            if selectedProviderID == "web:\(config.id)" {
                selectProvider(selectedProviderID, persistPreference: false)
            }
            let count = efforts.count
            let plural = count == 1 ? "" : "s"
            let message = String(format: L.t(AppLocalizationKey.locWebLoadedEffort), count, plural, config.displayName)
            return message + (localStorageWarning ?? "")
        } catch {
            return String(format: L.t(AppLocalizationKey.locWebEffortRefreshFailed), error.localizedDescription)
        }
        #else
        return L.t(AppLocalizationKey.locWebRequiresWebKit)
        #endif
    }

    /// Refresh the complete model capability snapshot. `refreshWebModels` already
    /// probes effort and parameter controls for every validated model; calling
    /// the older provider-global effort probe afterwards would overwrite the
    /// atomic per-model result with an ambiguous union.
    @MainActor
    func refreshWebModelsAndEffort(for config: WebProviderConfig,
                                   projectID: String? = nil,
                                   chatID: String? = nil) async -> (modelsMsg: String, effortMsg: String) {
        let modelsMsg = await refreshWebModels(for: config, projectID: projectID, chatID: chatID)
        let refreshedConfig = WebProviderStore.load().first(where: { $0.id == config.id }) ?? config
        let profiledCount = refreshedConfig.discoveredModels.filter { !$0.availableEfforts.isEmpty }.count
        let effortMsg = profiledCount == 0
            ? "No per-model effort controls were confirmed."
            : "Per-model effort detected for \(profiledCount) model(s)."
        return (modelsMsg, effortMsg)
    }


    /// Web providers whose chat session has already been seeded with the tool
    /// preamble this app run — so we send the preamble only on the first turn
    /// (audit P2). Reset when the session is (re)started/logged out.
    private var webSessionStarted: Set<String> = []
    func webSessionIsFirstTurn(_ providerID: String) -> Bool { !webSessionStarted.contains(providerID) }
    func markWebSessionStarted(_ providerID: String) { webSessionStarted.insert(providerID) }
    func resetWebSession(_ providerID: String) { webSessionStarted.remove(providerID) }

    func webSessionIsFirstTurn(_ key: WebRemoteChatKey) -> Bool { !webSessionStarted.contains(key.storageKey) }
    func markWebSessionStarted(_ key: WebRemoteChatKey) { webSessionStarted.insert(key.storageKey) }
    func resetWebSession(_ key: WebRemoteChatKey) { webSessionStarted.remove(key.storageKey) }

    /// Ids of enabled local providers (for send-routing / readiness checks).
    var localProviderIDs: [String] {
        LocalProviderLogic.load().filter { $0.isEnabled }.map { $0.id }
    }
    /// Ids of configured web providers (for send-routing / readiness checks).
    var webProviderIDs: [String] {
        WebProviderStore.load(defaults: defaults).map { $0.id }
    }

    var selectedProviderConnected: Bool {
        // Audit 2026-09-10: this getter runs on EVERY body evaluation
        // (StatusBar, chat input, send readiness) and used to redo JSON
        // decode + model-label regex + cookie-file reads per pass — with a
        // ticking parent that saturates the main thread and starves MainActor
        // API work. Cache briefly: connectivity is session-scoped and flips
        // on minute timescales (login/logout/session expiry), never within
        // seconds, so a 5 s TTL keeps the status dot truthful.
        let now = Date()
        if let cache = providerConnectedCache,
           cache.key == selectedProviderID,
           now.timeIntervalSince(cache.at) < Self.providerConnectedCacheTTL {
            return cache.value
        }
        let value = computeSelectedProviderConnected()
        providerConnectedCache = (key: selectedProviderID, value: value, at: now)
        return value
    }

    /// Invalidate the connectivity cache (call after login/logout/session
    /// capture so the UI reflects the new state immediately).
    func invalidateProviderConnectedCache() {
        providerConnectedCache = nil
    }

    private static let providerConnectedCacheTTL: TimeInterval = 5
    private var providerConnectedCache: (key: String, value: Bool, at: Date)?

    private func computeSelectedProviderConnected() -> Bool {
        let webConnected: Bool?
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           let config = WebProviderStore.load(defaults: defaults).first(where: { $0.id == webID }) {
            webConnected = WebProviderConnectivity.isConnected(
                config,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        } else {
            webConnected = nil
        }
        let localEnabled = LocalProviderLogic.load().contains {
            $0.id == selectedProviderID && $0.isEnabled
        }
        let customReady = customProviders.contains {
            $0.id == selectedProviderID
                && $0.isEnabled
                && (!$0.requiresAPIKey || !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let autoFreeReady = false
        return ProviderConnectionStatusLogic.isConnected(
            selectedID: selectedProviderID,
            serverProviderIDs: serverProviders
                .filter { !ProviderEnablementStore.isDisabled($0.id, defaults: defaults) }
                .map(\.id),
            serverConnected: serverConnected,
            autoFreeID: MyCoderAutoFreeProvider.builtInID,
            autoFreeReady: autoFreeReady,
            webConnected: webConnected,
            localEnabled: localEnabled,
            customReady: customReady,
            remembered: providerConnectivity[selectedProviderID]
        )
    }

    var currentSessionGoal: String? { selectedSession?.sessionGoal }

    /// Undo the most recent project-scoped file change and make every outcome
    /// visible. The old command discarded both the Bool result and thrown
    /// errors, leaving users unable to tell whether anything happened.
    @MainActor
    func undoLastAction() {
        guard selectedSession != nil else {
            publishShellActionNotice(
                UndoActionFeedbackLogic.message(for: .nothingToUndo),
                tone: UndoActionFeedbackLogic.tone(for: .nothingToUndo)
            )
            return
        }
        guard let projectUndoManager else {
            publishShellActionNotice(
                UndoActionFeedbackLogic.message(for: .nothingToUndo),
                tone: UndoActionFeedbackLogic.tone(for: .nothingToUndo)
            )
            return
        }
        let result: UndoActionResult
        do {
            let didUndo = try projectUndoManager.undoMostRecent(sessionId: selectedSession?.id ?? "")
            result = didUndo ? .undone : .nothingToUndo
        } catch {
            result = .failed(error.localizedDescription)
        }
        publishShellActionNotice(
            UndoActionFeedbackLogic.message(for: result),
            tone: UndoActionFeedbackLogic.tone(for: result)
        )
        if result == .undone {
            let directory = selectedWorkspace?.path
            Task { await refreshGitFromLocal(directory: directory) }
        }
    }

    @MainActor
    private func publishShellActionNotice(
        _ message: String,
        tone: UndoActionFeedbackTone
    ) {
        shellActionNotice = message
        shellActionNoticeTone = tone
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.shellActionNotice == message else { return }
                self?.shellActionNotice = nil
            }
        }
    }

    /// Set the goal on the selected session, persist in-memory and to the DB
    /// so it survives restarts (plan Раздел 5 Блок 1 п.10).
    func setCurrentSessionGoal(_ goal: String) {
        guard var session = selectedSession else { return }
        let value = SessionGoalPersistenceLogic.normalizedGoal(goal)
        session.sessionGoal = value
        selectedSession = session
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].sessionGoal = value
        }
        DatabaseBridge.shared.setSessionGoal(sessionId: session.id, goal: value)
    }

    /// Build the data context for the in-input command dropdown (plan Раздел 6).
    /// Cached project file list for `@` mentions (audit P12).
    private var projectFilesCache: ProjectFilesCacheState?
    private var projectFileIndexWatcher: ProjectFileIndexWatcher?
    private var projectFileIndexGeneration: UInt64 = 0

    private func updateProjectFileIndexWatcher(for workspace: Workspace?) {
        projectFileIndexGeneration &+= 1
        projectFileIndexWatcher?.stop()
        projectFileIndexWatcher = nil
        projectFilesCache = nil
        guard let workspace, !workspace.path.isEmpty else { return }

        let path = workspace.path
        let generation = projectFileIndexGeneration
        let watcher = ProjectFileIndexWatcher(
            projectPath: path,
            generation: generation
        ) { [weak self] eventPath, eventGeneration in
            DispatchQueue.main.async {
                guard let self,
                      ProjectFileIndexWatcherLogic.shouldApply(
                          eventProjectPath: eventPath,
                          activeProjectPath: self.selectedWorkspace?.path ?? "",
                          eventGeneration: eventGeneration,
                          activeGeneration: self.projectFileIndexGeneration
                      ) else { return }
                self.projectFilesCache = nil
            }
        }
        projectFileIndexWatcher = watcher
        watcher.start()
    }

    @MainActor
    func searchProjectFiles(query: String) -> [FileIndexRecord] {
        let path = selectedWorkspace?.path ?? ""
        guard !path.isEmpty else { return [] }
        if ProjectFilesCacheLogic.needsRescan(cache: projectFilesCache, currentPath: path) {
            let currentRecords = ProjectFileIndexStore.load(projectPath: path)
            let scannedRecords = ProjectFileScanner.scan(root: path)
            let records = ProjectFileIndexPersistenceLogic.applyDelta(current: currentRecords, scanned: scannedRecords)
            ProjectFileIndexStore.save(projectPath: path, records: records)
            projectFilesCache = ProjectFilesCacheState(
                projectPath: path,
                fileNames: records.map(\.path),
                scannedAt: Date()
            )
        }
        return ProjectFileSearchLogic.search(
            query: query,
            records: ProjectFileIndexStore.load(projectPath: path)
        )
    }

    func inputDropdownContext() -> InputDropdownDataSource.Context {
        let skills = AgentResourcesLoader.loadSkills().map { $0.name }
        let mcpServers = AgentResourcesLoader.loadMCPServers().map { $0.name }
        let sessionTitles = sessions.map { $0.title }
        let path = selectedWorkspace?.path ?? ""
        // Real project files for `@` — scan (cached, TTL) instead of empty list.
        if ProjectFilesCacheLogic.needsRescan(cache: projectFilesCache, currentPath: path) {
            let currentRecords = ProjectFileIndexStore.load(projectPath: path)
            let scannedRecords = ProjectFileScanner.scan(root: path)
            let records = ProjectFileIndexPersistenceLogic.applyDelta(current: currentRecords, scanned: scannedRecords)
            ProjectFileIndexStore.save(projectPath: path, records: records)
            projectFilesCache = ProjectFilesCacheState(
                projectPath: path,
                fileNames: records.map(\.path),
                scannedAt: Date()
            )
        }
        let fileNames = ProjectFilesCacheLogic.fileNames(cache: projectFilesCache, currentPath: path)
        return InputDropdownDataSource.Context(
            commands: SlashCommandRegistry.allCommands(),
            installedSkills: skills,
            fileNames: fileNames,
            sessionTitles: sessionTitles,
            mcpServers: mcpServers
        )
    }

    func loadCustomProviders() {
        if let data = defaults.data(forKey: "com.mycoder.customProviders"),
           let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) {
            customProviders = providers
            // Restore apiKey from Keychain for any provider that has been migrated
            for i in customProviders.indices {
                if customProviders[i].apiKey.isEmpty {
                    if let keychainKey = DatabaseBridge.shared.getProviderAPIKey(providerId: customProviders[i].id) {
                        customProviders[i].apiKey = keychainKey
                    }
                }
            }
            let deduplicated = ProviderDuplicationLogic.removingDuplicates(customProviders)
            if deduplicated.count != customProviders.count {
                for removed in customProviders where !deduplicated.contains(where: { $0.id == removed.id }) {
                    DatabaseBridge.shared.deleteProviderAPIKey(providerId: removed.id)
                }
                customProviders = deduplicated
                saveCustomProviders()
            }
        }
        for provider in customProviders where provider.isEnabled {
            loadModelsFromCustomProvider(provider)
        }
        validateAndReconcileSelections()
    }
    
    func connectToServe(hostname: String, port: Int) async {
        let newClient = MimoServeClient(host: hostname, port: port)
        
        await MainActor.run {
            self.serverHost = hostname
            self.serverPort = port
            self.mimoClient = newClient
            ServerProviderCatalogStore.saveConnection(host: hostname, port: port, defaults: self.defaults)
            // An explicit connection opts into the startup probe from now on.
            self.defaults.set(true, forKey: "com.mycoder.serverConnectionEnabled")
        }
        
        do {
            let health = try await newClient.health()
            await MainActor.run {
                self.serverConnected = health.healthy
                if health.healthy {
                    self.notificationService.serverConnected()
                }
            }
            if health.healthy {
                await loadModelsFromServer()
                await syncAccessLevelFromServer()
            }
        } catch {
            MyCoderAPIServer.appendLog("Connection failed: \(error)")
            await MainActor.run {
                self.serverConnected = false
                self.notificationService.serverDisconnected()
            }
        }
    }
    
    func stopServe() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.serverConnected = false
            self.notificationService.serverDisconnected()
            self.serverProviders = []
            // Disconnecting also drops the opt-in for the startup probe.
            self.defaults.set(false, forKey: "com.mycoder.serverConnectionEnabled")
            ServerProviderCatalogStore.save([], defaults: self.defaults)
            if !self.customProviders.contains(where: { $0.id == self.selectedProviderID && $0.isEnabled }) {
                if let firstCustom = self.customProviders.first(where: { $0.isEnabled }) {
                    self.selectProvider(firstCustom.id)
                } else {
                    self.selectedProviderID = ""
                    self.selectedModel = ""
                    self.selectedVariant = ""
                    self.defaults.set("", forKey: "com.mycoder.selectedProviderID")
                    self.defaults.set("", forKey: "com.mycoder.selectedModel")
                }
            } else {
                self.validateAndReconcileSelections()
            }
        }
    }
    
    func sessions(for workspace: Workspace) -> [ChatSession] {
        sessions
            .filter { $0.belongs(to: workspace) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Restore the last opened project at startup (user directive 2026-09-08).
    /// Pure resolution lives in WorkspaceRestoreLogic; this only wires the
    /// persisted id into `selectWorkspace` (which loads the project sessions).
    @MainActor
    func restoreLastWorkspace() {
        guard selectedWorkspace == nil else { return }
        let savedID = defaults.string(forKey: "com.mycoder.lastWorkspaceID")
        guard let workspace = WorkspaceRestoreLogic.restore(
            workspaces: workspaces,
            savedID: savedID
        ) else { return }
        selectWorkspace(workspace)
    }

    func selectWorkspace(_ workspace: Workspace, reloadSessions: Bool = true) {
        let previousID = selectedWorkspace?.id
        selectedWorkspace = workspace
        // User directive 2026-09-08: reopen the last project on app launch.
        defaults.set(workspace.id, forKey: "com.mycoder.lastWorkspaceID")
        restoreSpecWizardGate(for: workspace)
        // The synthetic "Chats" group is not a project: there is no project
        // database to load, so wiping here strands the list until the next
        // restart (the "+" on a project-less chat did exactly this). Merge
        // standalone rows synchronously instead.
        if workspace.id == ChatSession.standaloneProjectKey {
            selectedSession = nil
            sessions = DatabaseBridge.shared.loadStandaloneSessions()
            return
        }
        guard reloadSessions,
              WorkspaceSelectionLogic.shouldReloadSessions(previousID: previousID, newID: workspace.id) else {
            return
        }

        // Do not show the previous project's sessions while the new project's
        // database is loading. ChatPanel observes the nil selection and clears
        // its message store before the new session list arrives.
        selectedSession = nil
        sessions = []
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadSessionsFromDatabase(projectId: workspace.id)
        }
    }

    func selectSession(_ session: ChatSession) {
        // A sidebar cache can outlive the chat it points at (deleted through
        // the API, another window, or an older build). Selecting such a row
        // used to open a permanently empty chat; drop the row instead.
        let isInMemory = sessions.contains { $0.id == session.id }
        let existsInStore = isInMemory || DatabaseBridge.shared.sessionExists(id: session.id)
        if SessionSelectionGuardLogic.decision(
            sessionIsInMemory: isInMemory,
            sessionExistsInStore: existsInStore
        ) == .removeStaleRow {
            removeSessionFromInMemoryState(id: session.id)
            shellActionNotice = "This chat no longer exists — it was removed from the list."
            shellActionNoticeTone = .error
            MyCoderAPIServer.appendLog("🗑 removed stale sidebar chat: id=\(session.id)")
            return
        }
        if let workspace = workspaces.first(where: { session.belongs(to: $0) }) {
            selectWorkspace(workspace)
        }
        selectedSession = session
        restoreSelection(for: session)
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        refreshSubagentSessions()
        scheduleGitRefresh(sessionID: session.id)
        
        // Unarchive session if it was archived (so user can resume chatting)
        Task {
            try? DatabaseManager.shared.unarchiveSession(id: session.id)
        }
    }

    /// Reload the sub-agent list for the selected chat from its own store.
    func refreshSubagentSessions() {
        guard let session = selectedSession else {
            subagentSessions = []
            return
        }
        let projectKey = selectedWorkspace?.id ?? ChatSession.standaloneProjectKey
        subagentSessions = DatabaseBridge.shared.loadChildSessions(
            parentID: session.id,
            projectKey: projectKey
        )
    }

    func scheduleGitRefresh(sessionID explicitSessionID: String? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let sessionID = await MainActor.run {
                GitRefreshScheduler.resolvedSessionID(
                    explicit: explicitSessionID,
                    selected: self.selectedSession?.id
                )
            }
            if let sessionID {
                await self.loadSessionContext(sessionID: sessionID)
            } else {
                _ = await self.refreshGitFromLocal()
            }
        }
    }

    func loadSessionContext(sessionID: String) async {
        let context = await MainActor.run { () -> (directory: String?, summary: MimoSessionSummary?) in
            let session = self.sessions.first(where: { $0.id == sessionID }) ?? self.selectedSession
            let directory = SessionContextLoader.gitDirectoryPath(
                workspacePath: self.selectedWorkspace?.path,
                sessionDirectory: session?.directory
            )
            return (directory, session?.gitSummary)
        }

        let localResult = await refreshGitFromLocal(directory: context.directory)

        let shouldFetchRemote = SessionContextLoader.shouldFetchRemoteGit(
            localChangeCount: localResult.changeCount,
            localGitFailed: localResult.failed
        )
        guard shouldFetchRemote else { return }

        do {
            let diff = try await mimoClient.vcsDiff(directory: context.directory, mode: .git)
            let totals = SessionContextLoader.gitTotals(vcsFiles: diff.files, sessionSummary: context.summary)
            await MainActor.run {
                self.vcsChanges = diff.files
                self.sessionGitTotals = totals
                self.gitStatusMessage = nil
            }
        } catch {
            await MainActor.run {
                if let summary = context.summary {
                    self.sessionGitTotals = SessionContextLoader.gitTotals(vcsFiles: [], sessionSummary: summary)
                }
            }
            print("Failed to load session git context: \(error)")
        }
    }

    struct GitRefreshResult {
        let changeCount: Int
        let failed: Bool
    }

    @discardableResult
    func refreshGitFromLocal(directory: String? = nil) async -> GitRefreshResult {
        let key = directory ?? "__default__"
        return await gitRefreshCoalescer.run(key: key) {
            await self.performRefreshGitFromLocal(directory: directory)
        }
    }

    private func performRefreshGitFromLocal(directory: String?) async -> GitRefreshResult {
        let resolvedDirectory = await MainActor.run { () -> String? in
            if let directory {
                return directory
            }
            return SessionContextLoader.gitDirectoryPath(
                workspacePath: self.selectedWorkspace?.path,
                sessionDirectory: self.selectedSession?.directory
            )
        }

        guard let workspacePath = resolvedDirectory else {
            await MainActor.run {
                gitRepositoryPath = nil
            }
            return GitRefreshResult(changeCount: 0, failed: true)
        }

        await beginGitBusy()
        defer { Task { await self.endGitBusy() } }

        let snapshot = await Task.detached(priority: .utility) { () -> (result: GitRefreshResult, payload: GitRefreshPayload?) in
            do {
                let root = try GitRepository.repositoryRoot(for: workspacePath)
                let branch = GitRepository.currentBranch(in: root)
                let branches = try GitRepository.branches(in: root)
                let localChanges = try GitRepository.workingTreeChanges(in: root)
                let vcs = GitRepository.toVcsFileDiffs(localChanges)
                return (
                    GitRefreshResult(changeCount: vcs.count, failed: false),
                    GitRefreshPayload(
                        root: root,
                        branch: branch,
                        branches: branches,
                        vcs: vcs,
                        errorMessage: nil
                    )
                )
            } catch {
                return (
                    GitRefreshResult(changeCount: 0, failed: true),
                    GitRefreshPayload(
                        root: nil,
                        branch: nil,
                        branches: nil,
                        vcs: nil,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }.value

        await MainActor.run {
            if let payload = snapshot.payload, let root = payload.root, let branch = payload.branch,
               let branches = payload.branches, let vcs = payload.vcs {
                self.gitRepositoryPath = root
                self.gitBranch = branch
                self.gitBranches = branches
                self.vcsChanges = vcs
                self.sessionGitTotals = SessionContextLoader.gitTotals(vcsFiles: vcs, sessionSummary: nil)
                self.gitStatusMessage = nil
                self.updateWorkspaceBranch(branch)
            } else if let message = snapshot.payload?.errorMessage {
                self.gitStatusMessage = message
            }
        }

        return snapshot.result
    }

    private struct GitRefreshPayload {
        let root: String?
        let branch: String?
        let branches: [String]?
        let vcs: [MimoVcsFileDiff]?
        let errorMessage: String?
    }

    private func beginGitBusy() async {
        await MainActor.run {
            gitBusyCount += 1
            isGitBusy = true
        }
    }

    private func endGitBusy() async {
        await MainActor.run {
            gitBusyCount = max(0, gitBusyCount - 1)
            isGitBusy = gitBusyCount > 0
        }
    }

    @discardableResult
    func commitGitChanges(message: String) async -> Bool {
        guard let repoPath = gitRepositoryPath ?? selectedWorkspace.flatMap({ try? GitRepository.repositoryRoot(for: $0.path) }) else {
            await MainActor.run { gitStatusMessage = "No git repository for this workspace" }
            return false
        }

        await beginGitBusy()
        await MainActor.run { gitStatusMessage = nil }
        defer { Task { await self.endGitBusy() } }

        do {
            let result = try await Task.detached(priority: .utility) {
                try GitRepository.commitAll(in: repoPath, message: message)
            }.value
            await MainActor.run {
                gitStatusMessage = result.output.isEmpty ? "Committed successfully" : result.output
                notificationService.gitOperationComplete(operation: "Commit", details: message.prefix(80).description)
            }
            await refreshGitFromLocal()
            return true
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
            return false
        }
    }

    func pushGitChanges() async {
        guard let repoPath = gitRepositoryPath else {
            await MainActor.run { gitStatusMessage = "No git repository for this workspace" }
            return
        }

        await beginGitBusy()
        await MainActor.run { gitStatusMessage = nil }
        defer { Task { await self.endGitBusy() } }

        do {
            let result = try await Task.detached(priority: .utility) {
                try GitRepository.push(in: repoPath)
            }.value
            await MainActor.run {
                gitStatusMessage = result.output.isEmpty ? "Pushed successfully" : result.output
                notificationService.gitOperationComplete(operation: "Push", details: result.output.isEmpty ? "Changes pushed to remote" : result.output)
            }
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
        }
    }

    func checkoutGitBranch(_ branch: String) async {
        guard let repoPath = gitRepositoryPath else { return }

        await beginGitBusy()
        defer { Task { await self.endGitBusy() } }

        do {
            _ = try await Task.detached(priority: .utility) {
                try GitRepository.checkout(branch: branch, in: repoPath)
            }.value
            await refreshGitFromLocal()
            await MainActor.run {
                gitStatusMessage = "Switched to \(branch)"
            }
        } catch {
            await MainActor.run {
                gitStatusMessage = error.localizedDescription
            }
        }
    }

    /// Publishes the current workspace as a new GitHub repository via `gh`
    /// (shared by the publish wizard and the `/pr` slash command — E08).
    func publishWorkspaceToGitHub(ghPath: String, repoName: String, isPublic: Bool) async {
        guard let path = selectedWorkspace?.path else { return }
        guard GitPublishFlowLogic.isValidRepoName(repoName) else { return }

        await MainActor.run {
            isGitBusy = true
            gitStatusMessage = "Publishing to GitHub..."
        }

        do {
            let output = try await GitHubCLIService.createRepository(
                ghPath: ghPath,
                repoName: repoName,
                isPublic: isPublic,
                workspacePath: path
            )
            await MainActor.run {
                isGitBusy = false
                gitStatusMessage = output.isEmpty ? "Published to GitHub successfully!" : output
            }
            await refreshGitFromLocal()
        } catch {
            await MainActor.run {
                isGitBusy = false
                gitStatusMessage = "Failed to publish: \(error.localizedDescription)"
            }
        }
    }

    /// Creates a pull request for the current branch via `gh pr create`
    /// (Раздел 5 п.16 — real action for `/pr`).
    @discardableResult
    func createGitHubPullRequest(title: String, body: String) async -> Bool {
        guard let path = selectedWorkspace?.path,
              let ghPath = GitPublishFlowLogic.ghExecutablePath() else {
            await MainActor.run { gitStatusMessage = "GitHub CLI is not available — use the publish wizard." }
            return false
        }

        await MainActor.run {
            isGitBusy = true
            gitStatusMessage = "Creating pull request..."
        }
        defer { Task { await self.endGitBusy() } }

        do {
            let output = try await GitHubCLIService.createPullRequest(
                ghPath: ghPath,
                title: title,
                body: body,
                workspacePath: path
            )
            await MainActor.run {
                gitStatusMessage = output.isEmpty ? "Pull request created" : output
                notificationService.gitOperationComplete(operation: "PR", details: title)
            }
            return true
        } catch {
            await MainActor.run {
                gitStatusMessage = "Failed to create PR: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func updateWorkspaceBranch(_ branch: String) {
        guard var workspace = selectedWorkspace else { return }
        workspace.branch = branch
        selectedWorkspace = workspace
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index].branch = branch
        }
        if var session = selectedSession {
            session.branch = branch
            selectedSession = session
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index].branch = branch
            }
        }
    }

    func applySessionPlan(from serverMessages: [MimoMessageResponse]) {
        let steps = SessionPlanParser.steps(from: serverMessages)
        if !steps.isEmpty {
            currentSteps = steps
        }
    }
    
    func startNewTask(in workspace: Workspace? = nil) {
        if let workspace {
            selectWorkspace(workspace)
        }
        selectedSession = nil
        selectedTask = nil
        isLoading = false
        isStreaming = false
        currentSteps = []
        vcsChanges = []
        sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
        showGoal = false
        inputFocusRequest += 1
    }

    /// Create the local project-scoped session required before the first user
    /// or assistant message is appended. Serve used to create its remote
    /// session later, which meant the earlier MessageStore.append calls saw a
    /// nil currentSessionID and silently skipped local persistence.
    @MainActor
    // MARK: - Standalone chats (no project)

    /// Synthetic workspace representing the sidebar "Chats" group: every
    /// conversation that does not belong to a real project directory.
    var standaloneWorkspace: Workspace {
        Workspace(
            id: ChatSession.standaloneProjectKey,
            name: L.t("Chats"),
            path: ChatSession.standaloneProjectKey,
            tasks: []
        )
    }

    /// True when the app works without a project — a chat that is not tied to
    /// any project folder.
    var isProjectlessMode: Bool {
        ProjectlessWorkspaceLogic.isProjectless(selectedWorkspace)
    }

    /// Working directory of the open chat: the project folder for a project
    /// chat, the home folder for a project-less one. Every tool call, shell
    /// command and file read is resolved against it.
    var toolWorkingDirectory: String {
        ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: selectedSession?.directory,
            workspacePath: selectedWorkspace?.path
        )
    }

    /// Switch to the "no project" mode: chats are not tied to a project folder.
    @MainActor
    func selectNoProject() {
        selectWorkspace(standaloneWorkspace)
    }

    /// Start a new chat without a project.
    @MainActor
    func startProjectlessTask() {
        selectNoProject()
        startNewTask(in: standaloneWorkspace)
    }

    /// Conversations that belong to no workspace (audit 2026-09-08). New
    /// standalone chats carry the reserved directory key; legacy in-flight
    /// API chats (temp directory, never persisted) match the "no workspace"
    /// branch so they remain visible until the app restarts.
    var standaloneSessions: [ChatSession] {
        sessions
            .filter { session in
                if session.directory == ChatSession.standaloneProjectKey { return true }
                return !workspaces.contains { session.belongs(to: $0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Create a persisted standalone chat: stored in the global database
    /// under the reserved `standalone` project key, inserted into the
    /// in-memory list, NOT selected (caller decides).
    @MainActor
    @discardableResult
    func createStandaloneSession(title: String) -> ChatSession {
        let sessionID = UUID().uuidString
        let sessionTitle = ChatTitleLogic.title(for: title, existingTitles: sessions.map(\.title))
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: ChatSession.standaloneProjectKey,
            title: sessionTitle,
            directory: ChatSession.standaloneProjectKey,
            branch: nil,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        let session = ChatSession(
            id: sessionID,
            title: sessionTitle,
            directory: ChatSession.standaloneProjectKey,
            modelID: selectedModel.isEmpty ? nil : selectedModel,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        MyCoderAPIServer.appendLog("📝 createStandaloneSession: id=\(sessionID), title=\(sessionTitle)")
        return session
    }

    /// Put a chat into the sidebar caches so a freshly created chat shows up
    /// right away.
    ///
    /// The sidebar keeps its own per-project cache; a chat that only lands in
    /// the in-memory list stays invisible there until the project is reloaded
    /// — which is why a new chat could not be found in the list.
    @MainActor
    func registerSessionInSidebar(_ session: ChatSession) {
        if let workspace = workspaces.first(where: { session.belongs(to: $0) }) {
            var projectSessions = sidebarProjectSessions[workspace.id] ?? []
            projectSessions.removeAll { $0.id == session.id }
            projectSessions.insert(session, at: 0)
            sidebarProjectSessions[workspace.id] = projectSessions
            return
        }
        var projectless = sidebarProjectlessSessions
        projectless.removeAll { $0.id == session.id }
        projectless.insert(session, at: 0)
        sidebarProjectlessSessions = projectless
    }

    /// Drop a deleted/archived chat from every in-memory list the sidebar
    /// renders. Deleting used to touch `sessions` only, leaving the sidebar's
    /// own caches holding rows whose history no longer existed — clicking one
    /// opened an empty chat.
    func removeSessionFromInMemoryState(id: String) {
        sessions = SidebarSessionRemovalLogic.removing(id: id, from: sessions)
        sidebarProjectSessions = SidebarSessionRemovalLogic.removing(
            id: id,
            from: sidebarProjectSessions
        )
        sidebarProjectlessSessions = SidebarSessionRemovalLogic.removing(
            id: id,
            from: sidebarProjectlessSessions
        )
        pinnedSidebarItemIDs.remove(SidebarPinID.chat(id))
        streamingSessionIDs.remove(id)
        if selectedSession?.id == id {
            selectedSession = nil
        }
        if messageFocusRequest?.sessionID == id {
            messageFocusRequest = nil
        }
    }

    /// Resolve a chat for notification/deep-link navigation, materializing it
    /// from a sidebar cache or the database when it is not in `sessions`.
    @MainActor
    func sessionForNavigation(id: String) -> ChatSession? {
        if let session = sessions.first(where: { $0.id == id }) {
            return session
        }
        if let cached = sidebarKnownSessions.first(where: { $0.id == id }) {
            return cached
        }
        return materializeSessionFromDatabase(id: id)
    }

    /// Ask the chat panel to scroll to one concrete message. The token makes
    /// repeated taps on the same notification trigger a fresh scroll.
    @MainActor
    func requestMessageFocus(sessionID: String, messageID: String) {
        messageFocusRequest = MessageFocusRequest(
            sessionID: sessionID,
            messageID: messageID
        )
    }

    /// Consume a focus request once the chat panel applied it.
    @MainActor
    func clearMessageFocus(id: UUID) {
        guard messageFocusRequest?.id == id else { return }
        messageFocusRequest = nil
    }

    /// Merge persisted standalone chats into the in-memory list at startup
    /// (audit 2026-09-08 — they used to vanish after every restart).
    @MainActor
    func loadStandaloneSessionsIntoState() {
        let stored = DatabaseBridge.shared.loadStandaloneSessions()
        guard !stored.isEmpty else { return }
        let existing = Set(sessions.map(\.id))
        let missing = stored.filter { !existing.contains($0.id) }
        guard !missing.isEmpty else { return }
        sessions.append(contentsOf: missing)
        updateSidebarProjectlessSessions(stored)
        MyCoderAPIServer.appendLog("📝 loadStandaloneSessionsIntoState: +\(missing.count) standalone chats")
    }

    /// Materialize one persisted session into state by id (audit 2026-09-09):
    /// API/UI requests arriving during startup (or addressing a chat that was
    /// never merged into memory) must resolve to the STORED chat instead of
    /// spawning a duplicate. Returns the session when found in memory or in
    /// the standalone store.
    @MainActor
    @discardableResult
    func materializeSessionFromDatabase(id: String) -> ChatSession? {
        if let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        if let stored = DatabaseBridge.shared.loadStandaloneSessions().first(where: { $0.id == id }) {
            sessions.insert(stored, at: 0)
            registerSessionInSidebar(stored)
            MyCoderAPIServer.appendLog("📝 materializeSessionFromDatabase: +\(id)")
            return stored
        }
        return nil
    }

    @MainActor
    func prepareLocalSessionForSend(title: String) -> String? {
        if let selectedID = selectedSession?.id {
            return selectedID
        }
        return createLocalSessionForSend(title: title)
    }

    /// Always creates a fresh chat in the selected workspace (or a standalone
    /// chat when none is selected). Used by spec-node coding, which must not
    /// reuse whatever chat happened to be open.
    @MainActor
    func createLocalSessionForSend(title: String) -> String? {
        // Audit 2026-09-08: a chat started with NO workspace selected is a
        // standalone chat — it must persist and stay visible in the sidebar's
        // Chats group (user directive: standalone chats kept disappearing).
        guard let workspace = selectedWorkspace else {
            let session = createStandaloneSession(title: title)
            return session.id
        }
        let sessionID = UUID().uuidString
        let sessionTitle = ChatTitleLogic.title(for: title, existingTitles: sessions.map(\.title))
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: workspace.path,
            title: sessionTitle,
            directory: workspace.path,
            branch: workspace.branch,
            agentMode: agentMode.rawValue,
            modelId: selectedModel.isEmpty ? nil : selectedModel,
            providerId: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        let session = ChatSession(
            id: sessionID,
            title: sessionTitle,
            directory: workspace.path,
            branch: workspace.branch,
            modelID: selectedModel.isEmpty ? nil : selectedModel,
            providerID: selectedProviderID.isEmpty ? nil : selectedProviderID
        )
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        return sessionID
    }
    
    func openSkillsSettings() {
        settingsTab = .skills
        showSettings = true
    }
    
    func openFolderInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    func openSettings() {
        showSettings = true
    }
    
    @MainActor
    func upsertSession(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
        selectedSession = session
        MyCoderAPIServer.appendLog("📝 upsertSession: id=\(session.id), sessions=\(sessions.count), selected=\(selectedSession?.id ?? "nil")")
    }
    
    @MainActor
    func registerSessionFromServer(id: String, title: String, directory: String, select: Bool = true) {
        let session = ChatSession(
            id: id,
            title: title,
            directory: directory,
            branch: selectedWorkspace?.branch
        )
        if select {
            upsertSession(session)
        } else if !sessions.contains(where: { $0.id == id }) {
            sessions.insert(session, at: 0)
        }
        registerSessionInSidebar(session)
    }
    
    @discardableResult
    @MainActor
    func addWorkspace(path: String, branch: String? = nil) -> Workspace {
        let normalized = ChatSession.normalizedPath(path)
        if let existing = workspaces.first(where: { ChatSession.normalizedPath($0.path) == normalized }) {
            createOrUpdateProject(id: existing.id, name: existing.name, path: normalized, gitBranch: existing.branch)
            selectWorkspace(existing)
            return existing
        }
        
        // Round 14 (п.17/п.18): a project's id is its canonical path — never a
        // fresh UUID, so the DB row, registry entry, sessions and navigation
        // all agree on ONE identity (the old code minted a second UUID here).
        let workspace = Workspace(
            id: ProjectIdentityLogic.projectID(for: normalized),
            name: (normalized as NSString).lastPathComponent,
            path: normalized,
            branch: branch,
            tasks: []
        )
        workspaces.append(workspace)
        selectWorkspace(workspace, reloadSessions: false)
        // The database row IS the registration: Storage/Sidebar read the
        // `projects` table, so no side registry needs to be updated here.
        createOrUpdateProject(id: workspace.id, name: workspace.name, path: normalized, gitBranch: branch)
        return workspace
    }
    
    /// Создать новый проект: добавляет workspace и сохраняет в БД
    @MainActor
    func createNewProject(name: String, path: String) {
        let normalizedPath = ChatSession.normalizedPath(path)
        // Round 14 (п.18): the id must be the canonical path (same as
        // addWorkspace), NOT a random UUID — the two callers used to emit two
        // different ids for the same folder.
        let projectId = ProjectIdentityLogic.projectID(for: normalizedPath)
        
        // Сохраняем в БД
        createOrUpdateProject(id: projectId, name: name, path: normalizedPath)
        
        // Clear any stale wizard draft from a previous project at this path
        DatabaseBridge.shared.clearSpecWizardDraft(projectPath: normalizedPath)
        
        // Evict any stale wizard session for this path so a new project
        // gets a fresh session (not a cached session from a previous project
        // at the same location).
        SpecWizardSessionStore.shared.evict(projectPath: normalizedPath)
        
        // Добавляем workspace если его ещё нет (addWorkspace also registers
        // the project in the registry — Round 14 п.11).
        addWorkspace(path: normalizedPath)
    }

    // MARK: - Spec wizard entry

    /// A wizard draft stored in the project database re-opens the wizard when
    /// the project is selected again (including after an app restart). Forced
    /// or completed drafts never block chat.
    private func restoreSpecWizardGate(for workspace: Workspace) {
        guard workspace.id != ChatSession.standaloneProjectKey else { return }
        let path = ChatSession.normalizedPath(workspace.path)
        Task { @MainActor in
            guard !self.dismissedSpecWizardPaths.contains(path) else { return }
            guard let draft = DatabaseBridge.shared.loadSpecWizardDraft(projectPath: path) else { return }
            guard self.selectedWorkspace.map({ ChatSession.normalizedPath($0.path) }) == path else { return }
            if draft.status == .draft {
                self.activeSpecWizardProjectPath = path
            } else if self.activeSpecWizardProjectPath == path {
                self.activeSpecWizardProjectPath = nil
            }
        }
    }

    func beginProjectCreation(mode: ProjectCreationMode) {
        projectCreationMode = mode
        showProjectCreation = true
    }

    func openSpecWizard(for projectPath: String) {
        let path = ChatSession.normalizedPath(projectPath)
        dismissedSpecWizardPaths.remove(path)
        activeSpecWizardProjectPath = path
    }

    /// Creates a dedicated chat for the next runnable task, links it to the
    /// node, and queues the coder prompt. The prompt is sent by ChatPanelView
    /// after the new chat's history has loaded, so it cannot race the load and
    /// disappear. Returns nil (and leaves the node pending) on failure.
    @MainActor
    @discardableResult
    func startSpecNodeCoding(wizard: SpecWizardSession, node: ProjectSpecNode) -> ChatSession? {
        let path = ChatSession.normalizedPath(wizard.projectPath)
        guard let workspace = workspaces.first(where: {
            ChatSession.normalizedPath($0.path) == path
        }) else {
            wizard.errorMessage = "Project workspace not found"
            return nil
        }
        if selectedWorkspace?.id != workspace.id {
            selectWorkspace(workspace)
        }
        let title = "\(node.externalKey) · \(node.title)"
        guard let sessionID = createLocalSessionForSend(title: title) else {
            wizard.errorMessage = "Could not create a coding chat"
            return nil
        }
        guard let prompt = wizard.startCoding(nodeID: node.id, sessionID: sessionID),
              let chat = sessions.first(where: { $0.id == sessionID }) else {
            _ = DatabaseBridge.shared.deleteSession(id: sessionID)
            sessions.removeAll { $0.id == sessionID }
            return nil
        }
        selectSession(chat)
        if wizard.draft.status == .draft {
            // Starting a task means the plan is accepted; keep the finished
            // project from re-gating chat after a relaunch.
            _ = wizard.finishWizard(forced: false)
        }
        pendingSpecNodePrompt = PendingSpecNodePrompt(
            id: UUID().uuidString,
            sessionID: sessionID,
            text: prompt
        )
        finishSpecWizard(for: wizard.projectPath)
        return chat
    }

    /// Reopens the chat linked to a task. Returns nil when the task was never
    /// started or its chat no longer exists.
    @MainActor
    @discardableResult
    func openSpecNodeChat(wizard: SpecWizardSession, nodeID: String) -> ChatSession? {
        guard let link = wizard.nodeSessions(for: nodeID).last else {
            wizard.errorMessage = "Coding chat not found"
            return nil
        }
        let path = ChatSession.normalizedPath(wizard.projectPath)
        let stored = DatabaseBridge.shared.loadSessions(projectId: path)
            .first(where: { $0.id == link.sessionID })
        guard let chat = sessions.first(where: { $0.id == link.sessionID })
                ?? stored
                ?? materializeSessionFromDatabase(id: link.sessionID) else {
            wizard.errorMessage = "Coding chat not found"
            return nil
        }
        selectSession(chat)
        finishSpecWizard(for: wizard.projectPath)
        return chat
    }

    func finishSpecWizard(for projectPath: String) {
        let path = ChatSession.normalizedPath(projectPath)
        dismissedSpecWizardPaths.insert(path)
        if activeSpecWizardProjectPath == path {
            activeSpecWizardProjectPath = nil
        }
    }
}
