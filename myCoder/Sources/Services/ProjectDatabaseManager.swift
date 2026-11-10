import Foundation
import SQLite
import CryptoKit
#if canImport(SQLite3)
import SQLite3
#endif


/// Manages a single SQLite database scoped to exactly one project directory,
/// stored at `<project>/.mycoder/project.db`. Unlike the legacy global
/// `DatabaseManager` (one shared file for every project on the machine),
/// every project gets its own isolated file containing its full dialog
/// history, request history, and undo stack.
///
/// Instances are only ever created through the `manager(forProjectPath:)`
/// pool so that concurrent callers reuse the same open SQLite connection
/// per project instead of racing to open the file multiple times.
final class ProjectDatabaseManager {
    static let schemaVersion = 1

    /// Normalized absolute path to the project root this database belongs to.
    let projectPath: String
    let databaseFileURL: URL

    let db: Connection
    /// Serializes `lastAccessedAt` mutation/reads: `touch()` runs on the
    /// static pool queue while other threads read the property directly;
    /// an unsynchronized Date write is a data race (audit ARCH-03).
    let accessLock = NSLock()
    var lastAccessedAt: Date {
        accessLock.lock()
        defer { accessLock.unlock() }
        return _lastAccessedAt
    }
    var _lastAccessedAt: Date

    /// Current SQLite journal mode of the connection — "wal" after the E21
    /// setup in `openConnection`. Exposed for diagnostics and the E21 test.
    /// (Stepped via `failableNext` — `.next()` force-unwraps the step error.)
    var journalMode: String? {
        guard let statement = try? db.prepare("PRAGMA journal_mode"),
              let row = try? statement.failableNext(),
              let mode = row[0] as? String else { return nil }
        return mode
    }

    // MARK: - Table Definitions (mirrors the shape of the legacy global schema,
    // minus the now-redundant `project_id` column since the file itself is
    // already scoped to one project).

    let sessions = Table("sessions")
    let sessionId = Expression<String>("id")
    let sessionTitle = Expression<String>("title")
    let sessionCreatedAt = Expression<Int64>("created_at")
    let sessionUpdatedAt = Expression<Int64>("updated_at")
    let sessionDirectory = Expression<String>("directory")
    let sessionBranch = Expression<String?>("branch")
    let sessionAgentMode = Expression<String>("agent_mode")
    let sessionModelId = Expression<String?>("model_id")
    let sessionProviderId = Expression<String?>("provider_id")
    let sessionParentId = Expression<String?>("parent_session_id")
    let sessionSubagentStatus = Expression<String?>("subagent_status")
    let sessionIsArchived = Expression<Bool>("is_archived")
    let sessionTokensUsed = Expression<Int64>("tokens_used")
    let sessionCostUsd = Expression<Double>("cost_usd")
    let sessionActiveTimeSeconds = Expression<Int64>("active_time_seconds")
    let sessionMetadata = Expression<String?>("metadata")
    let sessionGoal = Expression<String?>("session_goal")

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

    let fileChanges = Table("file_changes")
    let fileChangeId = Expression<String>("id")
    let fileChangeToolCallId = Expression<String>("tool_call_id")
    let fileChangePath = Expression<String>("file_path")
    let fileChangeOperation = Expression<String>("operation")
    let fileChangeContentBefore = Expression<Data?>("content_before_compressed")
    let fileChangeContentAfter = Expression<Data?>("content_after_compressed")
    let fileChangeDiff = Expression<String?>("diff")
    let fileChangeTimestamp = Expression<Int64>("timestamp")

    let undoStack = Table("undo_stack")
    let undoId = Expression<String>("id")
    let undoSessionId = Expression<String>("session_id")
    let undoActionType = Expression<String>("action_type")
    let undoTargetPath = Expression<String?>("target_path")
    let undoSnapshotId = Expression<String?>("snapshot_id")
    let undoMetadata = Expression<String?>("metadata")
    let undoCreatedAt = Expression<Int64>("created_at")
    let undoCanUndo = Expression<Bool>("can_undo")

    let requestHistory = Table("request_history")
    let requestHistoryId = Expression<String>("id")
    let requestHistorySessionId = Expression<String?>("session_id")
    let requestHistoryType = Expression<String>("type")
    let requestHistoryPayload = Expression<String>("payload")
    let requestHistoryCreatedAt = Expression<Int64>("created_at")

    let projectMetadata = Table("project_metadata")
    let projectMetadataKey = Expression<String>("key")
    let projectMetadataValue = Expression<String>("value")

    // MARK: - Initialization

    private init(projectPath: String, databaseFileURL: URL, db: Connection) {
        self.projectPath = projectPath
        self.databaseFileURL = databaseFileURL
        self.db = db
        self._lastAccessedAt = Date()
    }

    /// Opens (creating if needed) the database for the given project path.
    /// The project directory must already exist on disk — this deliberately
    /// refuses to create directories for arbitrary strings so callers can't
    /// litter the filesystem by passing a non-project identifier by mistake.
    static func open(projectPath: String) throws -> ProjectDatabaseManager {
        try open(projectPath: projectPath,
                 homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Where the per-project DB file lives (E13, plan Раздел 8 п.51).
    /// Default: `<project>/.mycoder/project.db`. When that directory cannot be
    /// created (read-only / system-protected path), the DB falls back to
    /// `<home>/.mycoder/projects/<stable-hash>/project.db` so history and undo
    /// still work instead of the open failing. `attemptCreate` is injectable
    /// for deterministic tests; the default performs the real creation.
    /// Legacy `<project>/.mycoder` / `<home>/.mycoder` dirs migrate via MyCoderPaths.
    static func resolveDatabaseURL(
        projectPath: String,
        homeDirectory: URL,
        attemptCreate: (URL) -> Bool = { url in
            (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
        }
    ) -> URL {
        let inProject = MyCoderPaths.projectDataDir(projectPath: projectPath)
        if attemptCreate(inProject) {
            return inProject.appendingPathComponent("project.db")
        }
        let hash = stableHash(projectPath)
        let fallbackDir = MyCoderPaths.appDir(homeDirectory: homeDirectory)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
        _ = (try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true))
        return fallbackDir.appendingPathComponent("project.db")
    }

    /// Stable, path-derived identifier for the fallback DB directory
    /// (Foundation `hashValue` is randomized per process — not usable).
    static func stableHash(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// True when a per-project database file already exists for `projectPath`.
    /// Discovery uses it to avoid opening (and thereby creating) databases for
    /// registered projects the user never actually used.
    static func hasExistingDatabase(
        projectPath: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let normalized = ChatSession.normalizedPath(projectPath)
        let inProject = MyCoderPaths.projectDataDir(projectPath: normalized)
            .appendingPathComponent("project.db")
        if FileManager.default.fileExists(atPath: inProject.path) { return true }
        let fallback = MyCoderPaths.appDir(homeDirectory: homeDirectory)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(stableHash(normalized), isDirectory: true)
            .appendingPathComponent("project.db")
        return FileManager.default.fileExists(atPath: fallback.path)
    }

    /// `open(projectPath:)` with an injectable home directory. The home
    /// parameter keeps E13's read-only fallback testable without touching the
    /// real user home: a project on a read-only/system-protected path must
    /// still open, with its DB stored under `<home>/.mycoder/projects/<hash>/`.
    static func open(projectPath: String, homeDirectory: URL) throws -> ProjectDatabaseManager {
        let normalized = ChatSession.normalizedPath(projectPath)
        guard normalized.hasPrefix("/") else {
            throw ProjectDatabaseError.invalidProjectPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectDatabaseError.projectDirectoryNotFound(normalized)
        }

        // E13 (plan Раздел 8 п.51): the in-project `<project>/.mycoder/` dir is
        // used when writable; otherwise the DB falls back to
        // `<home>/.mycoder/projects/<stable-hash>/project.db` so read-only and
        // system-protected projects still open instead of failing.
        let dbURL = resolveDatabaseURL(projectPath: normalized, homeDirectory: homeDirectory)
        return try openConnection(atFileURL: dbURL, projectPath: normalized)
    }

    static func openConnection(atFileURL dbURL: URL, projectPath: String) throws -> ProjectDatabaseManager {
        let connection = try Connection(dbURL.path)
        connection.busyTimeout = 5.0
        // E21 (plan Раздел 7 п.46): WAL journaling — concurrent readers don't
        // block the writer and the -wal file makes crash recovery trivial.
        try connection.execute("PRAGMA journal_mode=WAL")

        let manager = ProjectDatabaseManager(projectPath: projectPath, databaseFileURL: dbURL, db: connection)
        try manager.createSchema()
        try manager.ensureStableProjectId()
        return manager
    }

    /// Creates an isolated in-memory database for unit tests that don't need
    /// real disk persistence but still want a valid, schema-complete instance.
    static func createInMemory(projectPath: String) throws -> ProjectDatabaseManager {
        let connection = try Connection(.inMemory)
        let normalized = ChatSession.normalizedPath(projectPath)
        let manager = ProjectDatabaseManager(
            projectPath: normalized,
            databaseFileURL: URL(fileURLWithPath: "/dev/null"),
            db: connection
        )
        try manager.createSchema()
        try manager.ensureStableProjectId()
        return manager
    }

    func touch() {
        accessLock.lock()
        _lastAccessedAt = Date()
        accessLock.unlock()
    }

    // MARK: - Pool

    static let poolQueue = DispatchQueue(label: "com.mimo.projectdb.pool")
    static var pool: [String: ProjectDatabaseManager] = [:]

    /// Returns the pooled manager for `path`, opening and caching a new one
    /// if none exists yet. Safe to call repeatedly with equivalent paths
    /// (trailing slashes, `..` components, etc.) — the pool key is always
    /// the standardized absolute path.
    static func manager(forProjectPath path: String) throws -> ProjectDatabaseManager {
        let normalized = ChatSession.normalizedPath(path)
        return try poolQueue.sync {
            if let existing = pool[normalized] {
                existing.touch()
                return existing
            }
            let created = try open(projectPath: normalized)
            pool[normalized] = created
            return created
        }
    }

    /// Closes and evicts every pooled connection whose `lastAccessedAt` is
    /// older than `interval` seconds. Intended to be called periodically
    /// (e.g. from a maintenance timer) so long-running sessions with many
    /// open projects don't keep hundreds of file handles alive forever.
    static func evictIdle(olderThan interval: TimeInterval = 600, now: Date = Date()) {
        poolQueue.sync {
            for (path, manager) in pool where now.timeIntervalSince(manager.lastAccessedAt) > interval {
                pool.removeValue(forKey: path)
            }
        }
    }

    /// Test/maintenance hook: drops every pooled connection unconditionally.
    static func evictAll() {
        poolQueue.sync { pool.removeAll() }
    }

    /// Drop the pooled connection for one specific project path (used before
    /// restoring a backup, so the restored file is read fresh, not the stale
    /// inode an open handle may still reference).
    static func evictProject(projectPath: String) {
        let normalized = ChatSession.normalizedPath(projectPath)
        _ = poolQueue.sync { pool.removeValue(forKey: normalized) }
    }

    static func isPooled(projectPath: String) -> Bool {
        let normalized = ChatSession.normalizedPath(projectPath)
        return poolQueue.sync { pool[normalized] != nil }
    }
}
