import Foundation

// MARK: - Error Types

enum DatabaseError: Error {
    case notInitialized
    case recordNotFound
    case invalidData
    case duplicateEntry
}

// MARK: - Record Types

struct ProjectRecord {
    let id: String
    let name: String
    let path: String
    let createdAt: Date
    let lastOpenedAt: Date
    let gitRemote: String?
    let gitBranch: String?
    let isPinned: Bool
    let stableId: String?
    let archivedAt: Date?
    let defaultProviderID: String?
    let defaultModelID: String?
}

/// One row of the database-backed project registry. `ProjectRegistryStore`
/// maps between this DTO and `ProjectRegistryEntry`; the database layer stays
/// free of UI/registry types.
struct ProjectRegistryRecord {
    let id: String
    let name: String
    let path: String
    let lastOpenedAt: Date
    let archivedAt: Date?
    let defaultProviderID: String?
    let defaultModelID: String?
}

struct SessionRecord {
    let id: String
    let projectId: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let directory: String
    let branch: String?
    let agentMode: String
    let isArchived: Bool
    let tokensUsed: Int
    let costUsd: Double
    let draftText: String?
    let modelId: String?
    let providerId: String?
    var parentSessionId: String? = nil
    var subagentStatus: String? = nil
}

struct MessageRecord {
    let id: String
    let sessionId: String
    let role: String
    let content: String
    let createdAt: Date
    let reasoning: String?
    let isFinished: Bool
    /// Token/cost accounting — carried over when a message is moved from the
    /// global store into a project database.
    var modelId: String? = nil
    var providerId: String? = nil
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var costUsd: Double? = nil
    /// JSON payload with the model + send parameters (`MessageSendInfo`).
    var metadata: String? = nil
}

struct MessagePartRecord {
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
