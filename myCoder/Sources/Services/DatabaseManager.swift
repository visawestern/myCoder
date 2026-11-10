import Foundation
import SQLite

/// Централизованный менеджер SQLite базы данных для MiMo
/// Использует SQLite.swift для type-safe queries
class DatabaseManager {
    static let shared = DatabaseManager()
    
    /// Current schema version — increment when tables change
    static let schemaVersion: Int = 6
    
    var db: Connection?
    let dbPath: String
    let isInMemory: Bool
    let queue = DispatchQueue(label: "com.mimo.database", qos: .userInitiated)
    
    // MARK: - Table Definitions
    
    // Projects table
    let projects = Table("projects")
    let projectId = Expression<String>("id")
    let projectName = Expression<String>("name")
    let projectPath = Expression<String>("path")
    let projectCreatedAt = Expression<Int64>("created_at")
    let projectLastOpenedAt = Expression<Int64>("last_opened_at")
    let projectGitRemote = Expression<String?>("git_remote")
    let projectGitBranch = Expression<String?>("git_branch")
    let projectIsPinned = Expression<Bool>("is_pinned")
    let projectColor = Expression<String?>("color")
    let projectIcon = Expression<String?>("icon")
    let projectMetadata = Expression<String?>("metadata")
    let projectDefaultAccessLevel = Expression<String?>("default_access_level")
    let projectCustomInstructions = Expression<String?>("custom_instructions")
    let projectEnvVars = Expression<Data?>("env_vars_encrypted")
    /// Minted once when a project is first registered and never changed
    /// afterwards, independent of `id` (which, per the storage-reset fix,
    /// equals the project's normalized path and therefore changes if the
    /// project is ever re-linked at a new path after being moved/renamed).
    let projectStableId = Expression<String?>("stable_id")
    /// Project administration state. It used to live in a side file
    /// (`~/.mycoder/projects.json`); the global database is now the single
    /// source of truth for projects (user directive 2026-10-28).
    let projectArchivedAt = Expression<Int64?>("archived_at")
    let projectDefaultProviderId = Expression<String?>("default_provider_id")
    let projectDefaultModelId = Expression<String?>("default_model_id")

    // Sessions table
    let sessions = Table("sessions")
    let sessionId = Expression<String>("id")
    let sessionProjectId = Expression<String>("project_id")
    let sessionTitle = Expression<String>("title")
    let sessionCreatedAt = Expression<Int64>("created_at")
    let sessionUpdatedAt = Expression<Int64>("updated_at")
    let sessionDirectory = Expression<String>("directory")
    let sessionBranch = Expression<String?>("branch")
    let sessionAgentMode = Expression<String>("agent_mode")
    let sessionModelId = Expression<String?>("model_id")
    let sessionProviderId = Expression<String?>("provider_id")
    let sessionParentId = Expression<String?>("parent_session_id")
    let sessionIsArchived = Expression<Bool>("is_archived")
    let sessionTokensUsed = Expression<Int64>("tokens_used")
    let sessionCostUsd = Expression<Double>("cost_usd")
    let sessionActiveTimeSeconds = Expression<Int64>("active_time_seconds")
    let sessionMetadata = Expression<String?>("metadata")
    let sessionGoal = Expression<String?>("session_goal")
    let sessionDraftText = Expression<String?>("draft_text")
    let sessionSubagentStatus = Expression<String?>("subagent_status")

    // Session routes table — durable mapping "session id -> owning project
    // path". Session/message storage lives in the per-project database, but
    // the in-memory routing map is rebuilt on every launch, so without this
    // table a session opened outside the project's own sidebar (recent chats,
    // grid view, deep link) resolves to no project at all and its history
    // lands in the global database instead of the project one.
    let sessionRoutes = Table("session_routes")
    let sessionRouteSessionId = Expression<String>("session_id")
    let sessionRouteProjectPath = Expression<String>("project_path")
    let sessionRouteUpdatedAt = Expression<Int64>("updated_at")
    
    // Messages table
    let messages = Table("messages")
    let messageId = Expression<String>("id")
    let messageSessionId = Expression<String>("session_id")
    let messageRole = Expression<String>("role")
    let messageContent = Expression<String>("content")
    let messageCreatedAt = Expression<Int64>("created_at")
    let messageModelId = Expression<String?>("model_id")
    let messageProviderId = Expression<String?>("provider_id")
    let messagePromptTokens = Expression<Int64?>("prompt_tokens")
    let messageCompletionTokens = Expression<Int64?>("completion_tokens")
    let messageCostUsd = Expression<Double?>("cost_usd")
    let messageReasoning = Expression<String?>("reasoning")
    let messageIsStreaming = Expression<Bool>("is_streaming")
    let messageIsFinished = Expression<Bool>("is_finished")
    let messageParentMessageId = Expression<String?>("parent_message_id")
    let messageEditOfMessageId = Expression<String?>("edit_of_message_id")
    let messageMetadata = Expression<String?>("metadata")
    
    // Message Parts table
    let messageParts = Table("message_parts")
    let partId = Expression<String>("id")
    let partMessageId = Expression<String>("message_id")
    let partType = Expression<String>("type")
    let partContent = Expression<String?>("content")
    let partToolName = Expression<String?>("tool_name")
    let partToolArgs = Expression<String?>("tool_args")
    let partToolResult = Expression<String?>("tool_result")
    let partToolCallId = Expression<String?>("tool_call_id")
    let partSequenceOrder = Expression<Int64>("sequence_order")
    
    // Tool Calls table
    let toolCalls = Table("tool_calls")
    let toolCallId = Expression<String>("id")
    let toolCallMessageId = Expression<String>("message_id")
    let toolCallName = Expression<String>("tool_name")
    let toolCallArguments = Expression<String>("arguments")
    let toolCallResult = Expression<String?>("result")
    let toolCallStatus = Expression<String>("status")
    let toolCallStartedAt = Expression<Int64>("started_at")
    let toolCallCompletedAt = Expression<Int64?>("completed_at")
    let toolCallErrorMessage = Expression<String?>("error_message")
    let toolCallExecutionTimeMs = Expression<Int64?>("execution_time_ms")
    
    // File Changes table
    let fileChanges = Table("file_changes")
    let fileChangeId = Expression<String>("id")
    let fileChangeToolCallId = Expression<String>("tool_call_id")
    let fileChangePath = Expression<String>("file_path")
    let fileChangeOperation = Expression<String>("operation")
    let fileChangeContentBefore = Expression<Data?>("content_before_compressed")
    let fileChangeContentAfter = Expression<Data?>("content_after_compressed")
    let fileChangeDiff = Expression<String?>("diff")
    let fileChangeTimestamp = Expression<Int64>("timestamp")
    
    // Undo Stack table
    let undoStack = Table("undo_stack")
    let undoId = Expression<String>("id")
    let undoSessionId = Expression<String>("session_id")
    let undoActionType = Expression<String>("action_type")
    let undoTargetPath = Expression<String?>("target_path")
    let undoSnapshotId = Expression<String?>("snapshot_id")
    let undoMetadata = Expression<String?>("metadata")
    let undoCreatedAt = Expression<Int64>("created_at")
    let undoCanUndo = Expression<Bool>("can_undo")
    
    // Providers table
    let providers = Table("providers")
    let providerId = Expression<String>("id")
    let providerName = Expression<String>("name")
    let providerType = Expression<String>("type")
    let providerApiKeyKeychainId = Expression<String?>("api_key_keychain_id")
    let providerBaseUrl = Expression<String?>("base_url")
    let providerIsEnabled = Expression<Bool>("is_enabled")
    let providerSupportsToolcall = Expression<Bool>("supports_toolcall")
    let providerSupportsAcp = Expression<Bool>("supports_acp")
    let providerIsOnline = Expression<Bool>("is_online")
    let providerLastHealthCheck = Expression<Int64?>("last_health_check")
    let providerCreatedAt = Expression<Int64>("created_at")
    let providerMetadata = Expression<String?>("metadata")
    
    // MARK: - Initialization
    
    private init() {
        // Audit 2026-09-13 (user DB pollution): `swift test` runs via
        // swift-testing, which does NOT load XCTest — the old "test" path
        // never fired and every DatabaseBridge.shared call in tests wrote
        // into the REAL ~/.mycoder/mycoder.db (245 junk sessions accumulated
        // across 106 runs, verified live). Under any test runner the
        // singleton becomes an in-memory database: tests that assert on it
        // still work, production data is never touched.
        if TestRunDetector.isRunningTests {
            self.isInMemory = true
            self.dbPath = ":memory:"
        } else {
            self.isInMemory = false
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let appDir = MyCoderPaths.appDir(homeDirectory: homeDir)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.dbPath = appDir.appendingPathComponent(MyCoderPaths.globalDatabaseFilename).path
        }
        initialize()
    }
    
    /// Create in-memory database for testing purposes
    static func createInMemory() -> DatabaseManager {
        let manager = DatabaseManager(inMemory: true)
        return manager
    }
    
    /// In-memory instance for tests (E30: a real DB with >100 projects must
    /// prove the sidebar list is not silently capped).
    init(inMemory: Bool) {
        self.isInMemory = true
        self.dbPath = ":memory:"
        initialize()
    }
    
    func initialize() {
        do {
            db = try Connection(dbPath)
            db?.busyTimeout = 5.0
            try createTables()
            try createIndexes()
            try createFTS5Index()
            try runMigrationsIfNeeded()
        } catch {
            print("❌ DatabaseManager init error: \(error)")
        }
    }
    
}

