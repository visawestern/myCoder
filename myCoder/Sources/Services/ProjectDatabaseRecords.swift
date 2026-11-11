import Foundation

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
    /// Номер сообщения модели, во время которого сделана правка. nil — запись
    /// создана старой версией или вне хода модели.
    let messageId: String?

    init(id: String, sessionId: String, actionType: String, targetPath: String?,
         snapshotId: String?, createdAt: Date, canUndo: Bool, messageId: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.actionType = actionType
        self.targetPath = targetPath
        self.snapshotId = snapshotId
        self.createdAt = createdAt
        self.canUndo = canUndo
        self.messageId = messageId
    }
}
