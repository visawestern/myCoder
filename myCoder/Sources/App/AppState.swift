import SwiftUI
import Foundation
import AppKit

/// Состояние приложения: выбранный проект, чаты, провайдеры
/// и всё, за чем наблюдает интерфейс.
///
/// Хранимые свойства живут здесь, поведение разнесено по
/// соседним файлам-расширениям.
///
/// Класс целиком изолирован на главном акторе: всё состояние интерфейса
/// читается и пишется только с главного потока, поэтому ни одно правило
/// интерфейса не может увидеть наполовину обновлённое состояние.
@MainActor
class AppState: ObservableObject {
    let instanceID = UUID().uuidString.prefix(8)
    deinit {
        if let observer = subagentObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = providersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = modelMetadataObserver {
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
    var dismissedSpecWizardPaths: Set<String> = []
    /// Coder prompt that must be sent once the selected chat is loaded.
    @Published var pendingSpecNodePrompt: PendingSpecNodePrompt?
    @Published var isStreaming = false
    @Published var isLoading = false
    /// Sessions with a live model turn (streaming or waiting for a plan
    /// question). The sidebar shows an activity indicator on those rows, so a
    /// turn that keeps running in the background stays visible while the user
    /// reads another chat.
    @Published var streamingSessionIDs: Set<String> = []
    /// Session whose chat history load is currently in flight. The composer
    /// shows the loading line while this is non-nil (mirrors
    /// `MessageStore.loadingSessionID`).
    @Published var loadingChatSessionID: String?
    /// Sessions with a context-assembly run in flight (C1). The composer line
    /// and the send guard read the SELECTED session's entry only, so a run in
    /// one chat never paints or blocks another chat.
    @Published var contextCompilingSessionIDs: Set<String> = []
    /// Current stage line per session (C1).
    @Published var contextPreparationStages: [String: String] = [:]
    /// Complete context-assembly journal per session (C1). The composer status
    /// line is a spoiler over the selected chat's journal.
    @Published var contextAssemblyLogs: [String: ContextAssemblyLogLogic.Log] = [:]
    /// Compaction that follows a model switch into a smaller context window.
    /// The chat compacts before it continues; the user can stop the
    /// compaction, roll it back, or pick a model with a larger window
    /// (user directive 2026-11-08).
    @Published var modelSwitchCompactionNotice: ModelSwitchCompactionNotice?
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
    @Published var providerConnectivity: [String: Bool] = [:]
    @Published var maxTokens = true
    @Published var askBeforeChanges = true
    @Published var sidebarVisible = true
    
    @Published var serverConnected = false
    @Published var serverHost = "127.0.0.1"
    @Published var serverPort = 4096
    @Published var serverProviders: [MimoProviderResponse] = []
    @Published var customProviders: [CustomProvider] = []
    /// Per-provider result of the last model refresh. Exposed in Settings so a
    /// bad URL, authentication failure, or unsupported response is actionable
    /// instead of looking like a mysterious empty model list.
    @Published var providerModelLoadMessages: [String: String] = [:]
    /// Bumped whenever a local/web provider config or custom-provider list is
    /// saved. Provider options are computed from disk-backed stores, so without
    /// this SwiftUI would not re-render the chat model menu after a Settings
    /// refresh (plan Раздел 1 п.3).
    @Published var providerCatalogRevision = 0
    /// Bumped whenever a manual model-metadata override changes. The context
    /// badge reads `ModelMetadataStore` directly, so SwiftUI needs a published
    /// signal to recalculate the window right after a Settings edit (C6).
    @Published private(set) var modelMetadataRevision = 0

    /// M1 model router: active routing configuration for the current
    /// project/chat. Loaded from `ModelRoutingStore` whenever the project or
    /// the open chat changes; assignments survive switching back to single
    /// mode (they are kept as an inactive configuration).
    @Published var modelRoutingConfiguration = ModelRoutingConfiguration()
    /// Whether the routing editor edits a chat override (true) or the project
    /// default (false).
    @Published var modelRoutingScopeIsChat = false
    /// Actually executed route nodes of the open chat — the panel only ever
    /// shows real runs, never promised ones. Mutated only through the routing
    /// APIs in `AppState+Routing.swift` (the setter must stay reachable from
    /// that extension file, so it is internal, not private(set)).
    @Published var modelRouteJournal: [TurnRouteJournalEntry] = []
    /// Bumped on every routing save so the composer label re-renders.
    @Published var modelRoutingRevision = 0

    @Published var workspaces: [Workspace] = []
    /// Lightweight registry snapshot used to reconcile sidebar visibility with
    /// Storage archive actions without hiding an unknown legacy workspace.
    @Published var projectRegistryEntries: [ProjectRegistryEntry] = []
    var isNavigatingHistory = false
    /// Pending message from local API. ChatPanelView observes this to trigger sends.
    @Published var apiPendingMessage: String?
    
    /// Guards navigationHistory/navigationIndex mutations. The `selectedWorkspace`
    /// didSet can fire from any thread (tests, background init tasks), so the
    /// truncate+append must be atomic or removeSubrange races into an
    /// out-of-range fatal error (Round 10 crash, still reproduced under parallel
    /// test runs — now fixed with a real lock, not just a bounds check).
    let navigationLock = NSLock()
    
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
    @Published var settings = AppSettings.load() {
        didSet {
            settings.save()
        }
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
    /// Execution steps per chat (C2). The header badge and the right panel
    /// read the SELECTED chat's steps, so a plan from chat A never appears in
    /// chat B.
    @Published var stepsBySessionID: [String: [TaskStep]] = [:]
    @Published var pendingQuestionRequest: PendingQuestionRequest?
    @Published var vcsChanges: [MimoVcsFileDiff] = []
    @Published var sessionGitTotals = SessionGitTotals(additions: 0, deletions: 0)
    /// Sub-agent chats of the selected session, shown in the right panel
    /// between the GitHub tools and the plan. Clicking a row navigates into
    /// the child chat transcript.
    @Published var subagentSessions: [ChatSession] = []
    /// Parent chat when the selected session is a sub-agent. The right panel
    /// keeps a back breadcrumb and lists the child's siblings instead of
    /// emptying itself after navigation.
    @Published var subagentParentSession: ChatSession?
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
    @Published var sidebarProjectSessions: [String: [ChatSession]] = [:]
    /// Chats that belong to no project. Each one becomes its own top-level
    /// sidebar row (F71).
    @Published var sidebarProjectlessSessions: [ChatSession] = []
    /// Sidebar rows pinned to the top (project ids and project-less chat ids).
    @Published var pinnedSidebarItemIDs: Set<String> = []
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
    @Published var messageFocusRequest: MessageFocusRequest?
    @Published var transientProviderNotification: AppNotification? = nil
    /// Short-lived feedback for shell actions such as Cmd+Option+Z.
    @Published var shellActionNotice: String?
    @Published var shellActionNoticeTone: UndoActionFeedbackTone = .success
    private var providersObserver: NSObjectProtocol? = nil
    private var subagentObserver: NSObjectProtocol? = nil
    private var modelMetadataObserver: NSObjectProtocol? = nil
    @Published var appTheme: AppTheme = .dark {
        didSet {
            defaults.set(appTheme.rawValue, forKey: "com.mycoder.theme")
            Color.mimo.setTheme(appTheme)
        }
    }
    
    var mimoClient: MimoServeClient
    var isSyncingAccessLevel = false
    let gitRefreshCoalescer = GitRefreshCoalescer()
    var gitBusyCount = 0
    
    // Database integration
    private var dbBridge: DatabaseBridge {
        DatabaseBridge.shared
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

        modelMetadataObserver = NotificationCenter.default.addObserver(
            forName: .modelMetadataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.modelMetadataRevision &+= 1
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
    
    /// Current session goal, shown in the TopBar (plan Раздел 5 Блок 1 п.9).

    @Published private(set) var webBrowserActionJournal: [WebBrowserActionRecord] = WebBrowserActionJournal.load()

    /// User directive 2026-09-09: the web provider's live browser page must be
    /// VISIBLE inside the chat as a mini-preview while a web provider is
    /// selected — no hidden offscreen window. The panel shows the AntiBrowser
    /// cast of the provider's tab, which keeps its login, conversation and
    /// in-flight stream across requests; switching chats points the panel at
    /// that chat's tab, exactly like opening another tab of the same site.
    /// Non-web providers leave the panel untouched (it keeps showing the last
    /// web provider's page).
    @Published var webBrowserPanelConfig: WebBrowserPanelConfig?

    /// Last web provider whose panel was shown. Hiding the panel clears
    /// `webBrowserPanelConfig` but keeps this id, so the top-bar Browser
    /// button can re-open the same tab (login and stream intact) even when the
    /// composer currently points at a non-web provider.
    @Published var webBrowserLastProviderID: String?

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

    /// Web providers whose chat session has already been seeded with the tool
    /// preamble this app run — so we send the preamble only on the first turn
    /// (audit P2). Reset when the session is (re)started/logged out.
    var webSessionStarted: Set<String> = []

    static let providerConnectedCacheTTL: TimeInterval = 5
    var providerConnectedCache: (key: String, value: Bool, at: Date)?

    /// Build the data context for the in-input command dropdown (plan Раздел 6).
    /// Serializes baseline builds and event-driven updates: two batches must
    /// never load the same snapshot, apply different changes and overwrite
    /// each other (last-writer-wins would silently lose an edit).
    let projectIndexUpdateQueue = DispatchQueue(
        label: "com.mycoder.project-index-update",
        qos: .utility
    )
    var projectFileIndexWatcher: ProjectFileIndexWatcher?
    var projectFileIndexGeneration: UInt64 = 0
}
