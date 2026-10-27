import Foundation
import SQLite
import CryptoKit
#if canImport(SQLite3)
import SQLite3
#endif

/// Errors raised while opening or operating on a per-project database.
enum ProjectDatabaseError: Error, LocalizedError, Equatable {
    case invalidProjectPath
    case projectDirectoryNotFound(String)
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath:
            return "Project path must be an absolute path"
        case .projectDirectoryNotFound(let path):
            return "Project directory does not exist on disk: \(path)"
        case .notInitialized:
            return "Project database connection is not initialized"
        }
    }
}

/// A record describing a single chat session stored inside a per-project database.
struct ProjectSessionRecord {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let directory: String
    let branch: String?
    let agentMode: String
    let isArchived: Bool
    let tokensUsed: Int
    let costUsd: Double
    let sessionGoal: String?
    let modelId: String?
    let providerId: String?
    var parentSessionId: String? = nil
    var subagentStatus: String? = nil
}

/// A record describing a single message stored inside a per-project database.
struct ProjectMessageRecord {
    let id: String
    let sessionId: String
    let role: String
    let content: String
    let createdAt: Date
    let reasoning: String?
    let isFinished: Bool
}

/// A record describing one rendered part of a message (text, reasoning, tool call, image, ...).
struct ProjectMessagePartRecord {
    let id: String
    let messageId: String
    let type: String
    let content: String?
    let toolName: String?
    let toolArgs: String?
    let toolResult: String?
    let toolCallId: String?
    let sequenceOrder: Int
}

/// A record describing a non-chat operation performed against the project
/// (file edits, executed commands, applied tool calls, ...), distinct from
/// ordinary chat messages so the full "request history" can be reconstructed.
struct ProjectRequestHistoryRecord {
    let id: String
    let sessionId: String?
    let type: String
    let payload: String
    let createdAt: Date
}

/// A single point-in-time undo entry: one file-affecting operation that can
/// be individually rolled back, independent of the other entries around it.
struct ProjectUndoEntryRecord {
    let id: String
    let sessionId: String
    let actionType: String
    let targetPath: String?
    let snapshotId: String?
    let createdAt: Date
    let canUndo: Bool
}

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

    private let db: Connection
    /// Serializes `lastAccessedAt` mutation/reads: `touch()` runs on the
    /// static pool queue while other threads read the property directly;
    /// an unsynchronized Date write is a data race (audit ARCH-03).
    private let accessLock = NSLock()
    private var lastAccessedAt: Date {
        accessLock.lock()
        defer { accessLock.unlock() }
        return _lastAccessedAt
    }
    private var _lastAccessedAt: Date

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

    private let sessions = Table("sessions")
    private let sessionId = Expression<String>("id")
    private let sessionTitle = Expression<String>("title")
    private let sessionCreatedAt = Expression<Int64>("created_at")
    private let sessionUpdatedAt = Expression<Int64>("updated_at")
    private let sessionDirectory = Expression<String>("directory")
    private let sessionBranch = Expression<String?>("branch")
    private let sessionAgentMode = Expression<String>("agent_mode")
    private let sessionModelId = Expression<String?>("model_id")
    private let sessionProviderId = Expression<String?>("provider_id")
    private let sessionParentId = Expression<String?>("parent_session_id")
    private let sessionSubagentStatus = Expression<String?>("subagent_status")
    private let sessionIsArchived = Expression<Bool>("is_archived")
    private let sessionTokensUsed = Expression<Int64>("tokens_used")
    private let sessionCostUsd = Expression<Double>("cost_usd")
    private let sessionActiveTimeSeconds = Expression<Int64>("active_time_seconds")
    private let sessionMetadata = Expression<String?>("metadata")
    private let sessionGoal = Expression<String?>("session_goal")

    private let messages = Table("messages")
    private let messageId = Expression<String>("id")
    private let messageSessionId = Expression<String>("session_id")
    private let messageRole = Expression<String>("role")
    private let messageContent = Expression<String>("content")
    private let messageCreatedAt = Expression<Int64>("created_at")
    private let messageModelId = Expression<String?>("model_id")
    private let messageProviderId = Expression<String?>("provider_id")
    private let messagePromptTokens = Expression<Int64?>("prompt_tokens")
    private let messageCompletionTokens = Expression<Int64?>("completion_tokens")
    private let messageCostUsd = Expression<Double?>("cost_usd")
    private let messageReasoning = Expression<String?>("reasoning")
    private let messageIsStreaming = Expression<Bool>("is_streaming")
    private let messageIsFinished = Expression<Bool>("is_finished")
    private let messageParentMessageId = Expression<String?>("parent_message_id")
    private let messageEditOfMessageId = Expression<String?>("edit_of_message_id")
    private let messageMetadata = Expression<String?>("metadata")

    private let messageParts = Table("message_parts")
    private let partId = Expression<String>("id")
    private let partMessageId = Expression<String>("message_id")
    private let partType = Expression<String>("type")
    private let partContent = Expression<String?>("content")
    private let partToolName = Expression<String?>("tool_name")
    private let partToolArgs = Expression<String?>("tool_args")
    private let partToolResult = Expression<String?>("tool_result")
    private let partToolCallId = Expression<String?>("tool_call_id")
    private let partSequenceOrder = Expression<Int64>("sequence_order")

    private let toolCalls = Table("tool_calls")
    private let toolCallId = Expression<String>("id")
    private let toolCallMessageId = Expression<String>("message_id")
    private let toolCallName = Expression<String>("tool_name")
    private let toolCallArguments = Expression<String>("arguments")
    private let toolCallResult = Expression<String?>("result")
    private let toolCallStatus = Expression<String>("status")
    private let toolCallStartedAt = Expression<Int64>("started_at")
    private let toolCallCompletedAt = Expression<Int64?>("completed_at")
    private let toolCallErrorMessage = Expression<String?>("error_message")
    private let toolCallExecutionTimeMs = Expression<Int64?>("execution_time_ms")

    private let fileChanges = Table("file_changes")
    private let fileChangeId = Expression<String>("id")
    private let fileChangeToolCallId = Expression<String>("tool_call_id")
    private let fileChangePath = Expression<String>("file_path")
    private let fileChangeOperation = Expression<String>("operation")
    private let fileChangeContentBefore = Expression<Data?>("content_before_compressed")
    private let fileChangeContentAfter = Expression<Data?>("content_after_compressed")
    private let fileChangeDiff = Expression<String?>("diff")
    private let fileChangeTimestamp = Expression<Int64>("timestamp")

    private let undoStack = Table("undo_stack")
    private let undoId = Expression<String>("id")
    private let undoSessionId = Expression<String>("session_id")
    private let undoActionType = Expression<String>("action_type")
    private let undoTargetPath = Expression<String?>("target_path")
    private let undoSnapshotId = Expression<String?>("snapshot_id")
    private let undoMetadata = Expression<String?>("metadata")
    private let undoCreatedAt = Expression<Int64>("created_at")
    private let undoCanUndo = Expression<Bool>("can_undo")

    private let requestHistory = Table("request_history")
    private let requestHistoryId = Expression<String>("id")
    private let requestHistorySessionId = Expression<String?>("session_id")
    private let requestHistoryType = Expression<String>("type")
    private let requestHistoryPayload = Expression<String>("payload")
    private let requestHistoryCreatedAt = Expression<Int64>("created_at")

    private let projectMetadata = Table("project_metadata")
    private let projectMetadataKey = Expression<String>("key")
    private let projectMetadataValue = Expression<String>("value")

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
    private static func open(projectPath: String) throws -> ProjectDatabaseManager {
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
    private static func stableHash(_ path: String) -> String {
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

    private static func openConnection(atFileURL dbURL: URL, projectPath: String) throws -> ProjectDatabaseManager {
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

    private func touch() {
        accessLock.lock()
        _lastAccessedAt = Date()
        accessLock.unlock()
    }

    // MARK: - Pool

    private static let poolQueue = DispatchQueue(label: "com.mimo.projectdb.pool")
    private static var pool: [String: ProjectDatabaseManager] = [:]

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

    // MARK: - Schema

    private func createSchema() throws {
        try db.run(sessions.create(ifNotExists: true) { t in
            t.column(sessionId, primaryKey: true)
            t.column(sessionTitle)
            t.column(sessionCreatedAt)
            t.column(sessionUpdatedAt)
            t.column(sessionDirectory)
            t.column(sessionBranch)
            t.column(sessionAgentMode, defaultValue: "build")
            t.column(sessionModelId)
            t.column(sessionProviderId)
            t.column(sessionParentId)
            t.column(sessionIsArchived, defaultValue: false)
            t.column(sessionTokensUsed, defaultValue: 0)
            t.column(sessionCostUsd, defaultValue: 0.0)
            t.column(sessionActiveTimeSeconds, defaultValue: 0)
            t.column(sessionMetadata)
            t.column(sessionGoal)
        })
        // Existing per-project databases predate session-goal persistence.
        // CREATE TABLE IF NOT EXISTS does not upgrade them, so add the column
        // explicitly while preserving all existing session rows.
        try addColumnIfMissing(table: "sessions", column: "session_goal", definition: "TEXT")
        try addColumnIfMissing(table: "sessions", column: "subagent_status", definition: "TEXT")

        try db.run(messages.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: true)
            t.column(messageSessionId)
            t.column(messageRole)
            t.column(messageContent)
            t.column(messageCreatedAt)
            t.column(messageModelId)
            t.column(messageProviderId)
            t.column(messagePromptTokens)
            t.column(messageCompletionTokens)
            t.column(messageCostUsd)
            t.column(messageReasoning)
            t.column(messageIsStreaming, defaultValue: false)
            t.column(messageIsFinished, defaultValue: true)
            t.column(messageParentMessageId)
            t.column(messageEditOfMessageId)
            t.column(messageMetadata)
            t.foreignKey(messageSessionId, references: sessions, sessionId, delete: .cascade)
        })
        // Existing project databases predate usage columns. `CREATE TABLE IF
        // NOT EXISTS` does not upgrade those tables, so make the column
        // contract explicit for databases opened after a schema change.
        try addColumnIfMissing(table: "messages", column: "cost_usd", definition: "REAL")

        try db.run(messageParts.create(ifNotExists: true) { t in
            t.column(partId, primaryKey: true)
            t.column(partMessageId)
            t.column(partType)
            t.column(partContent)
            t.column(partToolName)
            t.column(partToolArgs)
            t.column(partToolResult)
            t.column(partToolCallId)
            t.column(partSequenceOrder)
            t.foreignKey(partMessageId, references: messages, messageId, delete: .cascade)
        })

        try db.run(toolCalls.create(ifNotExists: true) { t in
            t.column(toolCallId, primaryKey: true)
            t.column(toolCallMessageId)
            t.column(toolCallName)
            t.column(toolCallArguments)
            t.column(toolCallResult)
            t.column(toolCallStatus)
            t.column(toolCallStartedAt)
            t.column(toolCallCompletedAt)
            t.column(toolCallErrorMessage)
            t.column(toolCallExecutionTimeMs)
            t.foreignKey(toolCallMessageId, references: messages, messageId, delete: .cascade)
        })

        try db.run(fileChanges.create(ifNotExists: true) { t in
            t.column(fileChangeId, primaryKey: true)
            t.column(fileChangeToolCallId)
            t.column(fileChangePath)
            t.column(fileChangeOperation)
            t.column(fileChangeContentBefore)
            t.column(fileChangeContentAfter)
            t.column(fileChangeDiff)
            t.column(fileChangeTimestamp)
            t.foreignKey(fileChangeToolCallId, references: toolCalls, toolCallId, delete: .cascade)
        })

        try db.run(undoStack.create(ifNotExists: true) { t in
            t.column(undoId, primaryKey: true)
            t.column(undoSessionId)
            t.column(undoActionType)
            t.column(undoTargetPath)
            t.column(undoSnapshotId)
            t.column(undoMetadata)
            t.column(undoCreatedAt)
            t.column(undoCanUndo, defaultValue: true)
            t.foreignKey(undoSessionId, references: sessions, sessionId, delete: .cascade)
        })

        try db.run(requestHistory.create(ifNotExists: true) { t in
            t.column(requestHistoryId, primaryKey: true)
            t.column(requestHistorySessionId)
            t.column(requestHistoryType)
            t.column(requestHistoryPayload)
            t.column(requestHistoryCreatedAt)
        })

        try db.run(projectMetadata.create(ifNotExists: true) { t in
            t.column(projectMetadataKey, primaryKey: true)
            t.column(projectMetadataValue)
        })

        try createSpecSchema()

        try db.run(sessions.createIndex(sessionUpdatedAt, ifNotExists: true))
        try db.run(sessions.createIndex(sessionIsArchived, ifNotExists: true))
        try db.run(messages.createIndex(messageSessionId, ifNotExists: true))
        try db.run(messages.createIndex([messageSessionId, messageCreatedAt], ifNotExists: true))
        try db.run(messageParts.createIndex([partMessageId, partSequenceOrder], ifNotExists: true))
        try db.run(toolCalls.createIndex(toolCallMessageId, ifNotExists: true))
        try db.run(fileChanges.createIndex(fileChangeToolCallId, ifNotExists: true))
        try db.run(undoStack.createIndex([undoSessionId, undoCreatedAt], ifNotExists: true))
        try db.run(requestHistory.createIndex([requestHistorySessionId, requestHistoryCreatedAt], ifNotExists: true))

        try createFTS5Index()
    }

    /// Specification wizard storage. Every table is scoped by `project_id`
    /// even though the database file already belongs to one project: the
    /// wizard keeps immutable TZ revisions and node history forever, and an
    /// explicit scope keeps future exports/merges unambiguous.
    ///
    /// No foreign keys here on purpose. Revisions, history and node sessions
    /// are an append-only audit trail; cascading deletes would silently erase
    /// exactly the data the wizard promises to preserve.
    private func createSpecSchema() throws {
        let settings = Table("project_spec_settings")
        try db.run(settings.create(ifNotExists: true) { t in
            t.column(Expression<String>("project_id"), primaryKey: true)
            t.column(Expression<String?>("planner_provider_id"))
            t.column(Expression<String?>("planner_model_id"))
            t.column(Expression<String?>("coder_provider_id"))
            t.column(Expression<String?>("coder_model_id"))
            t.column(Expression<String>("status"), defaultValue: "draft")
            t.column(Expression<String>("current_step"), defaultValue: "setup")
            t.column(Expression<String?>("brief_goal"))
            t.column(Expression<String?>("brief_stack"))
            t.column(Expression<String?>("brief_constraints"))
            t.column(Expression<Int64>("created_at"))
            t.column(Expression<Int64>("updated_at"))
            t.column(Expression<Int64?>("completed_at"))
        })

        let checklist = Table("spec_checklist_items")
        try db.run(checklist.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("item_key"))
            t.column(Expression<String>("title"))
            t.column(Expression<String>("state"))
            t.column(Expression<String?>("detail"))
            t.column(Expression<Int64>("sort_order"))
            t.column(Expression<Int64>("updated_at"))
            t.unique(Expression<String>("project_id"), Expression<String>("item_key"))
        })

        let turns = Table("spec_wizard_turns")
        try db.run(turns.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("role"))
            t.column(Expression<String>("content"))
            t.column(Expression<String?>("suggested_answers"))
            t.column(Expression<Int64>("sequence"))
            t.column(Expression<Int64>("created_at"))
        })

        let revisions = Table("spec_tz_revisions")
        try db.run(revisions.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<Int64>("version"))
            t.column(Expression<String>("content_markdown"))
            t.column(Expression<String?>("summary"))
            t.column(Expression<String>("source"))
            t.column(Expression<String?>("parent_revision_id"))
            t.column(Expression<Int64>("created_at"))
            t.unique(Expression<String>("project_id"), Expression<Int64>("version"))
        })

        let requirements = Table("spec_requirements")
        try db.run(requirements.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("revision_id"))
            t.column(Expression<String>("external_key"))
            t.column(Expression<String>("title"))
            t.column(Expression<String>("description"))
            t.column(Expression<String>("priority"))
            t.column(Expression<String>("status"))
            t.column(Expression<String?>("acceptance_criteria"))
            t.column(Expression<Int64>("created_at"))
            t.column(Expression<Int64>("updated_at"))
            t.unique(Expression<String>("revision_id"), Expression<String>("external_key"))
        })

        let nodes = Table("spec_nodes")
        try db.run(nodes.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("revision_id"))
            t.column(Expression<String>("external_key"))
            t.column(Expression<String>("title"))
            t.column(Expression<String>("description"))
            t.column(Expression<String>("kind"))
            t.column(Expression<String>("status"))
            t.column(Expression<Int64>("sort_order"))
            t.column(Expression<String?>("acceptance_criteria"))
            t.column(Expression<Int64>("created_at"))
            t.column(Expression<Int64>("updated_at"))
            t.unique(Expression<String>("revision_id"), Expression<String>("external_key"))
        })

        let edges = Table("spec_edges")
        try db.run(edges.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("from_node_id"))
            t.column(Expression<String>("to_node_id"))
            t.column(Expression<String>("kind"))
            t.column(Expression<Int64>("created_at"))
            t.unique(
                Expression<String>("project_id"),
                Expression<String>("from_node_id"),
                Expression<String>("to_node_id"),
                Expression<String>("kind")
            )
        })

        let history = Table("spec_history")
        try db.run(history.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("entity_type"))
            t.column(Expression<String>("entity_id"))
            t.column(Expression<String>("action"))
            t.column(Expression<String?>("payload"))
            t.column(Expression<String>("actor"))
            t.column(Expression<Int64>("created_at"))
        })

        let nodeSessions = Table("spec_node_sessions")
        try db.run(nodeSessions.create(ifNotExists: true) { t in
            t.column(Expression<String>("id"), primaryKey: true)
            t.column(Expression<String>("project_id"))
            t.column(Expression<String>("node_id"))
            t.column(Expression<String>("session_id"))
            t.column(Expression<String>("state"))
            t.column(Expression<Int64>("created_at"))
            t.column(Expression<Int64>("updated_at"))
            t.unique(Expression<String>("node_id"), Expression<String>("session_id"))
        })

        for sql in [
            "CREATE INDEX IF NOT EXISTS idx_spec_checklist_project_order ON spec_checklist_items(project_id, sort_order)",
            "CREATE INDEX IF NOT EXISTS idx_spec_turns_project_sequence ON spec_wizard_turns(project_id, sequence)",
            "CREATE INDEX IF NOT EXISTS idx_spec_tz_project_version ON spec_tz_revisions(project_id, version)",
            "CREATE INDEX IF NOT EXISTS idx_spec_requirements_revision ON spec_requirements(revision_id)",
            "CREATE INDEX IF NOT EXISTS idx_spec_nodes_revision_order ON spec_nodes(revision_id, sort_order)",
            "CREATE INDEX IF NOT EXISTS idx_spec_edges_project ON spec_edges(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_spec_history_project_created ON spec_history(project_id, created_at)",
            "CREATE INDEX IF NOT EXISTS idx_spec_node_sessions_node ON spec_node_sessions(node_id)"
        ] {
            try db.execute(sql)
        }
    }

    /// Validated SQL identifiers for `addColumnIfMissing`. SQL identifiers can
    /// never be parameterized, so instead of interpolating arbitrary caller
    /// strings (injection surface, audit ARCH-05) we validate against the
    /// actual table/column expressions this manager owns and build the
    /// statement only from the validated literals.
    private enum SchemaIdentifier {
        static let tables: Set<String> = [
            "sessions", "messages", "message_parts", "tool_calls",
            "file_changes", "undo_stack", "request_history", "project_metadata"
        ]
        static let columns: Set<String> = [
            "id", "session_id", "title", "created_at", "updated_at", "directory",
            "branch", "agent_mode", "model_id", "provider_id",
            "parent_session_id", "is_archived", "tokens_used", "cost_usd",
            "active_time_seconds", "metadata", "session_goal", "subagent_status",
            "message_id", "role", "content", "prompt_tokens", "completion_tokens",
            "reasoning", "is_streaming", "is_finished", "parent_message_id",
            "edit_of_message_id", "type", "tool_name", "tool_args", "tool_result",
            "tool_call_id", "sequence_order", "arguments", "status", "started_at",
            "completed_at", "error_message", "execution_time_ms",
            "session_goal",
            "tool_call_id", "file_path", "operation", "content_before_compressed",
            "content_after_compressed", "diff", "timestamp", "action_type",
            "target_path", "snapshot_id", "can_undo", "payload", "key", "value"
        ]

        static func validate(table: String, column: String) -> Bool {
            tables.contains(table) && columns.contains(column)
        }
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        guard SchemaIdentifier.validate(table: table, column: column) else {
            throw DatabaseValidationError.unallowedIdentifier("ALTER TABLE \(table) ADD COLUMN \(column) was rejected: identifier is not part of the owned schema")
        }
        let existingColumns = try SQLiteSafeQuery.rows(
            db.prepare("PRAGMA table_info(\(table))")
        ).compactMap { row -> String? in
            row[1] as? String
        }
        guard !existingColumns.contains(column) else { return }
        try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    enum DatabaseValidationError: LocalizedError {
        case unallowedIdentifier(String)

        var errorDescription: String? {
            switch self {
            case .unallowedIdentifier(let message): return message
            }
        }
    }

    private func createFTS5Index() throws {
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                content,
                session_title,
                file_paths,
                tool_names
            );
        """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(rowid, content, session_title, file_paths, tool_names)
                VALUES (new.rowid, new.content, '', '', '');
            END;
        """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                DELETE FROM messages_fts WHERE rowid = old.rowid;
            END;
        """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                DELETE FROM messages_fts WHERE rowid = old.rowid;
                INSERT INTO messages_fts(rowid, content, session_title, file_paths, tool_names)
                VALUES (new.rowid, new.content, '', '', '');
            END;
        """)
    }

    // MARK: - Stable Project Identity (survives folder rename/move)

    /// A UUID minted once, the first time this project's database is
    /// created, and never changed afterwards. Stored inside the project's
    /// own database file (not just in the global registry) so that if the
    /// project folder is later moved or renamed, the orphaned `.mycoder`
    /// directory can still be matched back to its registry entry by this id
    /// rather than by path alone.
    private func ensureStableProjectId() throws {
        if try db.pluck(projectMetadata.filter(projectMetadataKey == "stable_id")) != nil {
            return
        }
        try db.run(projectMetadata.insert(
            projectMetadataKey <- "stable_id",
            projectMetadataValue <- UUID().uuidString
        ))
    }

    func stableProjectId() throws -> String {
        guard let row = try db.pluck(projectMetadata.filter(projectMetadataKey == "stable_id")) else {
            throw ProjectDatabaseError.notInitialized
        }
        return row[projectMetadataValue]
    }

    /// Read/write the project-scoped key-value store. Used by the spec wizard
    /// so its draft survives app restarts without a separate global store.
    func metadataValue(forKey key: String) throws -> String? {
        touch()
        guard let row = try db.pluck(projectMetadata.filter(projectMetadataKey == key)) else {
            return nil
        }
        return row[projectMetadataValue]
    }

    func setMetadataValue(_ value: String, forKey key: String) throws {
        touch()
        try db.run(projectMetadata.insert(or: .replace,
                                          projectMetadataKey <- key,
                                          projectMetadataValue <- value))
    }

    /// Spec wizard storage shares this project's connection but owns its own
    /// table boundary. Keeping `db` private means callers cannot bypass the
    /// append-only rules implemented by the store.
    func makeSpecStore() -> ProjectSpecStore {
        touch()
        return ProjectSpecStore(db: db)
    }

    /// Project memory lives in the same database as sessions and the spec
    /// wizard. The table is created on first use, so an existing project
    /// database gains it without a migration step.
    func makeMemoryStore() throws -> ProjectMemoryStore {
        touch()
        try ProjectMemoryStore.createSchema(db)
        return ProjectMemoryStore(db: db)
    }

    /// The task ledger is one row per session in the same project database.
    func makeLedgerStore() throws -> TaskLedgerStore {
        touch()
        try TaskLedgerStore.createSchema(db)
        return TaskLedgerStore(db: db)
    }

    // MARK: - Session Operations

    func insertSession(
        id: String,
        title: String,
        directory: String,
        branch: String? = nil,
        agentMode: String = "build",
        modelId: String? = nil,
        providerId: String? = nil,
        parentSessionId: String? = nil,
        subagentStatus: String? = nil,
        sessionGoal: String? = nil
    ) throws {
        let sessionGoalValue = sessionGoal
        let subagentStatusValue = subagentStatus
        touch()
        let now = Int64(Date().timeIntervalSince1970)
        try db.run(sessions.insert(
            or: .replace,
            sessionId <- id,
            sessionTitle <- title,
            sessionCreatedAt <- now,
            sessionUpdatedAt <- now,
            sessionDirectory <- directory,
            sessionBranch <- branch,
            sessionAgentMode <- agentMode,
            sessionModelId <- modelId,
            sessionProviderId <- providerId,
            sessionParentId <- parentSessionId,
            sessionSubagentStatus <- subagentStatusValue,
            sessionIsArchived <- false,
            self.sessionGoal <- sessionGoalValue
        ))
    }

    /// Sub-agent chats spawned by `parentId`, newest first.
    func childSessions(parentId: String) throws -> [ProjectSessionRecord] {
        touch()
        return try SQLiteSafeQuery.rows(
            db.prepareRowIterator(sessions.filter(sessionParentId == parentId).order(sessionCreatedAt.asc))
        ).map(rowToSessionRecord)
    }

    /// Persist a sub-agent lifecycle status ("running" | "done" | "failed").
    func setSubagentStatus(id: String, status: String?) throws {
        touch()
        try db.run(sessions.filter(sessionId == id).update(sessionSubagentStatus <- status))
    }

    func getAllSessions(includeArchived: Bool = true) throws -> [ProjectSessionRecord] {
        touch()
        var query = sessions.order(sessionUpdatedAt.desc)
        if !includeArchived {
            query = sessions.filter(sessionIsArchived == false).order(sessionUpdatedAt.desc)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map(rowToSessionRecord)
    }

    /// True when this project store owns the given session id. Used to
    /// discover the owning project of a session whose in-memory route was
    /// lost (app restart) and no durable route row exists yet.
    func hasSession(id: String) throws -> Bool {
        touch()
        return try db.scalar(sessions.filter(sessionId == id).count) > 0
    }

    /// Persists the /goal value inside this project's database.
    /// nil clears the goal without touching unrelated session metadata.
    func setSessionGoal(id: String, goal: String?) throws {        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionGoal <- goal))
    }

    func updateSessionTimestamp(id: String) throws {
        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionUpdatedAt <- Int64(Date().timeIntervalSince1970)))
    }

    /// Persist the model and provider a chat uses, so reopening the chat
    /// restores the same selection.
    @discardableResult
    func updateSessionModel(id: String, modelId: String?, providerId: String?) throws -> Int {
        touch()
        let row = sessions.filter(sessionId == id)
        return try db.run(row.update(
            sessionModelId <- modelId,
            sessionProviderId <- providerId
        ))
    }

    /// Rename a session in this project store (sidebar context menu).
    /// Returns the number of rows updated so callers can detect a stale id
    /// instead of reporting success for a silent no-op.
    @discardableResult
    func updateSessionTitle(id: String, title: String) throws -> Int {
        touch()
        let row = sessions.filter(sessionId == id)
        return try db.run(row.update(
            sessionTitle <- title,
            sessionUpdatedAt <- Int64(Date().timeIntervalSince1970)
        ))
    }

    /// Hard-delete one session. SQLite foreign keys are OFF by default on the
    /// pooled connection, so dependents are deleted explicitly (schema FKs are
    /// declared but cannot be relied on here); without this, messages orphaned
    /// and a later session reusing the id would show stale history.
    @discardableResult
    func deleteSession(id: String) throws -> Bool {
        touch()
        let messageIDs = try SQLiteSafeQuery.rows(
            db.prepareRowIterator(messages.filter(messageSessionId == id).select(messageId))
        ).map { $0[messageId] }
        if !messageIDs.isEmpty {
            let callIDs = try SQLiteSafeQuery.rows(
                db.prepareRowIterator(toolCalls.filter(messageIDs.contains(toolCallMessageId)).select(toolCallId))
            ).map { $0[toolCallId] }
            if !callIDs.isEmpty {
                try db.run(fileChanges.filter(callIDs.contains(fileChangeToolCallId)).delete())
            }
            try db.run(toolCalls.filter(messageIDs.contains(toolCallMessageId)).delete())
            try db.run(messageParts.filter(messageIDs.contains(partMessageId)).delete())
            try db.run(messages.filter(messageIDs.contains(messageId)).delete())
        }
        try db.run(undoStack.filter(undoSessionId == id).delete())
        try db.run(requestHistory.filter(requestHistorySessionId == id).delete())
        return try db.run(sessions.filter(sessionId == id).delete()) > 0
    }

    func archiveSession(id: String) throws {
        touch()
        let row = sessions.filter(sessionId == id)
        try db.run(row.update(sessionIsArchived <- true))
    }

    func unarchiveSession(id: String) throws {
        touch()
        // Only an actually archived session changes state; otherwise every
        // chat click would bump `updated_at` and reorder the sidebar.
        //
        // The condition lives in the UPDATE itself: a separate read would
        // crash on a missing row or a NULL `is_archived` (SQLite.swift force
        // unwraps the scalar binding) and would race with a concurrent write.
        try db.run(
            "UPDATE sessions SET is_archived = 0, updated_at = ? WHERE id = ? AND is_archived IS NOT 0",
            Int64(Date().timeIntervalSince1970),
            id
        )
    }

    /// Archives active sessions older than the supplied age in this project DB.
    @discardableResult
    func archiveSessionsOlderThan(days: Int, now: Date = Date()) throws -> Int {
        touch()
        let cutoff = Int64(now.timeIntervalSince1970) - Int64(max(0, days) * 86400)
        let oldActive = sessions.filter(sessionIsArchived == false && sessionUpdatedAt < cutoff)
        return try db.run(oldActive.update(sessionIsArchived <- true))
    }

    /// Permanently deletes every archived session in this project DB.
    @discardableResult
    func deleteArchivedSessions() throws -> Int {
        touch()
        return try db.run(sessions.filter(sessionIsArchived == true).delete())
    }

    /// Permanently deletes sessions older than the supplied age in this project DB.
    @discardableResult
    func deleteSessionsOlderThan(days: Int, now: Date = Date()) throws -> Int {
        touch()
        let cutoff = Int64(now.timeIntervalSince1970) - Int64(max(0, days) * 86400)
        return try db.run(sessions.filter(sessionUpdatedAt < cutoff).delete())
    }

    private func rowToSessionRecord(_ row: Row) -> ProjectSessionRecord {
        ProjectSessionRecord(
            id: row[sessionId],
            title: row[sessionTitle],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row[sessionCreatedAt])),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row[sessionUpdatedAt])),
            directory: row[sessionDirectory],
            branch: row[sessionBranch],
            agentMode: row[sessionAgentMode],
            isArchived: row[sessionIsArchived],
            tokensUsed: Int(row[sessionTokensUsed]),
            costUsd: row[sessionCostUsd],
            sessionGoal: row[sessionGoal],
            modelId: row[sessionModelId],
            providerId: row[sessionProviderId],
            parentSessionId: row[sessionParentId],
            subagentStatus: row[sessionSubagentStatus]
        )
    }

    // MARK: - Message Operations

    func insertMessage(
        id: String,
        sessionId sessionIdValue: String,
        role: String,
        content: String,
        modelId: String? = nil,
        providerId: String? = nil,
        reasoning: String? = nil,
        isFinished: Bool = true,
        usage: UsageCapture? = nil,
        createdAt: Date? = nil
    ) throws {
        touch()
        let now = Int64(createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        try db.run(messages.insert(
            or: .replace,
            messageId <- id,
            messageSessionId <- sessionIdValue,
            messageRole <- role,
            messageContent <- content,
            messageCreatedAt <- now,
            messageModelId <- modelId ?? usage?.modelID,
            messageProviderId <- providerId ?? usage?.providerID,
            messagePromptTokens <- usage.map { Int64($0.promptTokens) },
            messageCompletionTokens <- usage.map { Int64($0.completionTokens) },
            messageCostUsd <- usage?.costUSD,
            messageReasoning <- reasoning,
            messageIsFinished <- isFinished
        ))
        if usage != nil {
            try recalculateSessionUsage(id: sessionIdValue)
        }
        try updateSessionTimestamp(id: sessionIdValue)
    }

    /// Update usage columns of an already-stored message. Returns true if a row
    /// was updated. No-op (returns false) when the message id is unknown.
    @discardableResult
    func updateMessageTokens(id: String, usage: UsageCapture) throws -> Bool {
        touch()
        let row = messages.filter(messageId == id)
        let count = try db.run(row.update(
            messagePromptTokens <- Int64(usage.promptTokens),
            messageCompletionTokens <- Int64(usage.completionTokens),
            messageCostUsd <- usage.costUSD,
            messageModelId <- usage.modelID,
            messageProviderId <- usage.providerID
        ))
        if count > 0, let sid = try db.pluck(row.select(messageSessionId))?[messageSessionId] {
            try updateSessionTimestamp(id: sid)
            try recalculateSessionUsage(id: sid)
        }
        return count > 0
    }

    /// Recompute and persist `tokens_used` / `cost_usd` for a session from its
    /// assistant messages. Call after any message usage change.
    private func recalculateSessionUsage(id: String) throws {
        var tokens: Int64 = 0
        var cost: Double = 0
        var hasCost = false
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(
            messages.select(messagePromptTokens, messageCompletionTokens, messageCostUsd)
                .filter(messageSessionId == id && messageRole == "assistant"))) {
            tokens += (row[messagePromptTokens] ?? 0) + (row[messageCompletionTokens] ?? 0)
            if let c = row[messageCostUsd] {
                cost += c
                hasCost = true
            }
        }
        let _ = try db.run(sessions.filter(sessionId == id).update(
            sessionTokensUsed <- tokens,
            sessionCostUsd <- hasCost ? cost : 0
        ))
    }

    /// Read per-message usage data points for statistics from this project DB.
    func usageDataPoints() throws -> [UsageDataPoint] {
        var points: [UsageDataPoint] = []
        let query = messages.filter(messageRole == "assistant")
        for row in try SQLiteSafeQuery.rows(db.prepareRowIterator(query)) {
            let prompt = Int(row[messagePromptTokens] ?? 0)
            let completion = Int(row[messageCompletionTokens] ?? 0)
            guard prompt > 0 || completion > 0 else { continue }
            let model = row[messageModelId] ?? "unknown"
            let provider = row[messageProviderId] ?? "unknown"
            let ts = Date(timeIntervalSince1970: TimeInterval(row[messageCreatedAt]))
            points.append(UsageDataPoint(
                timestamp: ts, model: model, provider: provider,
                promptTokens: prompt, completionTokens: completion, costUSD: row[messageCostUsd]
            ))
        }
        return points
    }

    func getMessages(sessionId sessionIdValue: String, limit: Int? = nil, offset: Int = 0) throws -> [ProjectMessageRecord] {
        touch()
        var query = messages.filter(messageSessionId == sessionIdValue).order(messageCreatedAt.asc)
        if let limit {
            query = query.limit(limit, offset: offset)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectMessageRecord(
                id: row[messageId],
                sessionId: row[messageSessionId],
                role: row[messageRole],
                content: row[messageContent],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[messageCreatedAt])),
                reasoning: row[messageReasoning],
                isFinished: row[messageIsFinished]
            )
        }
    }

    func insertMessagePart(
        id: String,
        messageId messageIdValue: String,
        type: String,
        content: String? = nil,
        toolName: String? = nil,
        toolArgs: String? = nil,
        toolResult: String? = nil,
        toolCallId: String? = nil,
        sequenceOrder: Int
    ) throws {
        touch()
        try db.run(messageParts.insert(
            or: .replace,
            partId <- id,
            partMessageId <- messageIdValue,
            partType <- type,
            partContent <- content,
            partToolName <- toolName,
            partToolArgs <- toolArgs,
            partToolResult <- toolResult,
            partToolCallId <- toolCallId,
            partSequenceOrder <- Int64(sequenceOrder)
        ))
    }

    /// Delete all stored parts of a message: a message is re-saved on every
    /// update, so stale part rows (removed from the in-memory set) must not
    /// survive alongside the fresh insert.
    func deleteMessageParts(messageId messageIdValue: String) throws {
        touch()
        try db.run(messageParts.filter(partMessageId == messageIdValue).delete())
    }

    func getMessageParts(messageId messageIdValue: String) throws -> [ProjectMessagePartRecord] {
        touch()
        let query = messageParts.filter(partMessageId == messageIdValue).order(partSequenceOrder.asc)
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectMessagePartRecord(
                id: row[partId],
                messageId: row[partMessageId],
                type: row[partType],
                content: row[partContent],
                toolName: row[partToolName],
                toolArgs: row[partToolArgs],
                toolResult: row[partToolResult],
                toolCallId: row[partToolCallId],
                sequenceOrder: Int(row[partSequenceOrder])
            )
        }
    }

    // MARK: - Request History (non-chat operations: file edits, commands, applied tool calls)

    func recordRequestHistory(sessionId sessionIdValue: String?, type: String, payload: String) throws {
        touch()
        try db.run(requestHistory.insert(
            requestHistoryId <- UUID().uuidString,
            requestHistorySessionId <- sessionIdValue,
            requestHistoryType <- type,
            requestHistoryPayload <- payload,
            requestHistoryCreatedAt <- Int64(Date().timeIntervalSince1970)
        ))
    }

    func getRequestHistory(sessionId sessionIdValue: String? = nil, limit: Int? = 200) throws -> [ProjectRequestHistoryRecord] {
        touch()
        var base = requestHistory
        if let sessionIdValue {
            base = base.filter(requestHistorySessionId == sessionIdValue)
        }
        var query = base.order(requestHistoryCreatedAt.asc)
        if let limit {
            query = base.order(requestHistoryCreatedAt.asc).limit(limit)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query)).map { row in
            ProjectRequestHistoryRecord(
                id: row[requestHistoryId],
                sessionId: row[requestHistorySessionId],
                type: row[requestHistoryType],
                payload: row[requestHistoryPayload],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[requestHistoryCreatedAt]))
            )
        }
    }

    // MARK: - Undo Stack (point-in-time, per-entry rollback)

    func insertUndoEntry(
        id: String,
        sessionId sessionIdValue: String,
        actionType: String,
        targetPath: String?,
        snapshotId: String?,
        metadata: String? = nil
    ) throws {
        touch()
        try db.run(undoStack.insert(
            or: .replace,
            undoId <- id,
            undoSessionId <- sessionIdValue,
            undoActionType <- actionType,
            undoTargetPath <- targetPath,
            undoSnapshotId <- snapshotId,
            undoMetadata <- metadata,
            undoCreatedAt <- Int64(Date().timeIntervalSince1970),
            undoCanUndo <- true
        ))
    }

    /// Returns undo entries newest-first, matching how a rollback list is
    /// presented to the user (most recent action on top).
    func getUndoStack(sessionId sessionIdValue: String, onlyUsable: Bool = false) throws -> [ProjectUndoEntryRecord] {
        touch()
        var query = undoStack.filter(undoSessionId == sessionIdValue)
        if onlyUsable {
            query = query.filter(undoCanUndo == true)
        }
        return try SQLiteSafeQuery.rows(db.prepareRowIterator(query.order(undoCreatedAt.desc))).map { row in
            ProjectUndoEntryRecord(
                id: row[undoId],
                sessionId: row[undoSessionId],
                actionType: row[undoActionType],
                targetPath: row[undoTargetPath],
                snapshotId: row[undoSnapshotId],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row[undoCreatedAt])),
                canUndo: row[undoCanUndo]
            )
        }
    }

    /// Marks a specific undo entry as consumed (soft delete), independent of
    /// every other entry — this is what makes point-in-time (not just
    /// "undo everything") rollback possible.
    func markUndoEntryUsed(id: String) throws {
        touch()
        let row = undoStack.filter(undoId == id)
        try db.run(row.update(undoCanUndo <- false))
    }

    func getUndoEntry(id: String) throws -> ProjectUndoEntryRecord? {
        touch()
        guard let row = try db.pluck(undoStack.filter(undoId == id)) else { return nil }
        return ProjectUndoEntryRecord(
            id: row[undoId],
            sessionId: row[undoSessionId],
            actionType: row[undoActionType],
            targetPath: row[undoTargetPath],
            snapshotId: row[undoSnapshotId],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row[undoCreatedAt])),
            canUndo: row[undoCanUndo]
        )
    }

    // MARK: - Full-Text Search

    func searchMessages(query: String, limit: Int = 50) throws -> [String] {
        touch()
        let sql = """
            SELECT messages.id FROM messages_fts
            JOIN messages ON messages.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var ids: [String] = []
        for row in try SQLiteSafeQuery.rows(db.prepare(sql, [query, limit])) {
            if let id = row[0] as? String {
                ids.append(id)
            }
        }
        return ids
    }

    // MARK: - Maintenance

    func vacuum() throws {
        try db.execute("VACUUM")
    }

    /// `PRAGMA integrity_quick_check` — returns nil when the database is intact,
    /// or a description of the corruption otherwise (plan Раздел 8 п.48).
    /// Uses the raw SQLite C API: the SQLite.swift wrapper doesn't surface
    /// PRAGMA result rows, and quick_check returns no rows on a fresh DB.
    func integrityCheck() throws -> String? {
        try Self.integrityQuickCheck(on: db)
    }

    /// Read-only `PRAGMA integrity_quick_check` against a bare connection.
    /// Used by `ProjectOpenIntegrity.checkOnOpen` so the open-time corruption
    /// probe never routes through `openConnection` (which runs `createSchema()`
    /// + `PRAGMA journal_mode=WAL` and would re-initialize a corrupt/garbage
    /// file, masking the corruption — a data-loss bug). A fresh read-only
    /// connection validates the on-disk file as-is, deterministically and
    /// independently of the connection-pool state.
    static func integrityQuickCheck(on connection: Connection) throws -> String? {
        let handle = connection.handle
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(NSMutableString()).toOpaque())
        let sql = "PRAGMA integrity_quick_check"
        let rc = sqlite3_exec(handle, sql, { ctx, colCount, values, _ in
            let result = Unmanaged<NSMutableString>.fromOpaque(ctx!).takeUnretainedValue()
            var parts: [String] = []
            for i in 0..<Int(colCount) {
                if let c = values![i] { parts.append(String(cString: c)) }
            }
            result.append(parts.joined(separator: ","))
            return 0
        }, context, nil)
        let collected = Unmanaged<NSMutableString>.fromOpaque(context).takeRetainedValue() as String
        guard rc == SQLITE_OK else { return "integrity check failed (rc \(rc))" }
        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "ok" ? nil : trimmed
    }

    func databaseFileSizeBytes() -> UInt64 {
        func size(_ url: URL) -> UInt64 {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
            return (attrs[.size] as? UInt64) ?? 0
        }
        // WAL (E21): the main .db file stays at its page size while new writes
        // land in the -wal sidecar, so "real on-disk usage" = db + wal + shm.
        return size(databaseFileURL)
            + size(URL(fileURLWithPath: databaseFileURL.path + "-wal"))
            + size(URL(fileURLWithPath: databaseFileURL.path + "-shm"))
    }

    func sessionCount() throws -> Int {
        try db.scalar(sessions.count)
    }

    func messageCount() throws -> Int {
        try db.scalar(messages.count)
    }

    /// Count messages of one session. Used for tail-paging the history
    /// (newest-N initial load + older pages) without fetching everything.
    func countMessages(sessionId sessionIdValue: String) throws -> Int {
        touch()
        return try db.scalar(messages.filter(messageSessionId == sessionIdValue).count)
    }

    /// User messages that carry visible text. The chat navigator numbers the
    /// user's own messages, and the numbering must span the whole session —
    /// not only the page that is currently loaded.
    func countUserMessages(sessionId sessionIdValue: String) throws -> Int {
        touch()
        let query = messages.filter(
            messageSessionId == sessionIdValue &&
            messageRole == "user" &&
            messageContent != ""
        )
        return try db.scalar(query.count)
    }
}
