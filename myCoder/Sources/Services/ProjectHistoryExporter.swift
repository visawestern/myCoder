import Foundation

/// Exports and re-imports the full dialog + request history of a single
/// project's `ProjectDatabaseManager` as a self-contained JSON bundle, for
/// manual backup/sharing or restoring a project's history on another
/// machine after a fresh install.
enum ProjectHistoryExporter {

    struct ExportedPart: Codable, Equatable {
        let id: String
        let type: String
        let content: String?
        let toolName: String?
        let toolArgs: String?
        let toolResult: String?
        let toolCallId: String?
        let sequenceOrder: Int
    }

    struct ExportedMessage: Codable, Equatable {
        let id: String
        let role: String
        let content: String
        let createdAt: Date
        let reasoning: String?
        let isFinished: Bool
        let parts: [ExportedPart]
    }

    struct ExportedSession: Codable, Equatable {
        let id: String
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let directory: String
        let branch: String?
        let agentMode: String
        let isArchived: Bool
        let messages: [ExportedMessage]
    }

    struct ExportedRequestHistoryEntry: Codable, Equatable {
        let id: String
        let sessionId: String?
        let type: String
        let payload: String
        let createdAt: Date
    }

    struct ExportBundle: Codable, Equatable {
        let schemaVersion: Int
        let exportedAt: Date
        let projectPath: String
        let stableProjectId: String
        let sessions: [ExportedSession]
        let requestHistory: [ExportedRequestHistoryEntry]
    }

    enum ExportError: Error, LocalizedError {
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                return "Cannot import export bundle with unsupported schema version \(version)"
            }
        }
    }

    private static let currentSchemaVersion = 1

    static func export(from db: ProjectDatabaseManager, now: Date = Date()) throws -> Data {
        let sessions = try db.getAllSessions()
        var exportedSessions: [ExportedSession] = []

        for session in sessions {
            let messages = try db.getMessages(sessionId: session.id)
            var exportedMessages: [ExportedMessage] = []
            for message in messages {
                let parts = try db.getMessageParts(messageId: message.id)
                let exportedParts = parts.map { part in
                    ExportedPart(
                        id: part.id,
                        type: part.type,
                        content: part.content,
                        toolName: part.toolName,
                        toolArgs: part.toolArgs,
                        toolResult: part.toolResult,
                        toolCallId: part.toolCallId,
                        sequenceOrder: part.sequenceOrder
                    )
                }
                exportedMessages.append(ExportedMessage(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    createdAt: message.createdAt,
                    reasoning: message.reasoning,
                    isFinished: message.isFinished,
                    parts: exportedParts
                ))
            }
            exportedSessions.append(ExportedSession(
                id: session.id,
                title: session.title,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                directory: session.directory,
                branch: session.branch,
                agentMode: session.agentMode,
                isArchived: session.isArchived,
                messages: exportedMessages
            ))
        }

        let requestHistory = try db.getRequestHistory(limit: nil)
        let exportedRequestHistory = requestHistory.map {
            ExportedRequestHistoryEntry(id: $0.id, sessionId: $0.sessionId, type: $0.type, payload: $0.payload, createdAt: $0.createdAt)
        }

        let bundle = ExportBundle(
            schemaVersion: currentSchemaVersion,
            exportedAt: now,
            projectPath: db.projectPath,
            stableProjectId: try db.stableProjectId(),
            sessions: exportedSessions,
            requestHistory: exportedRequestHistory
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    struct ImportSummary: Equatable {
        var importedSessions: Int = 0
        var importedMessages: Int = 0
        var importedRequestHistoryEntries: Int = 0
    }

    /// Restores an export bundle into `db`. Upserts by id, so importing the
    /// same bundle twice (or importing into a database that already has some
    /// overlapping sessions) never creates duplicates.
    @discardableResult
    static func importBundle(_ data: Data, into db: ProjectDatabaseManager) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        guard bundle.schemaVersion == currentSchemaVersion else {
            throw ExportError.unsupportedSchemaVersion(bundle.schemaVersion)
        }

        var summary = ImportSummary()

        for session in bundle.sessions {
            try db.insertSession(
                id: session.id,
                title: session.title,
                directory: session.directory,
                branch: session.branch,
                agentMode: session.agentMode
            )
            if session.isArchived {
                try db.archiveSession(id: session.id)
            }
            summary.importedSessions += 1

            for message in session.messages {
                try db.insertMessage(
                    id: message.id,
                    sessionId: session.id,
                    role: message.role,
                    content: message.content,
                    reasoning: message.reasoning,
                    isFinished: message.isFinished
                )
                summary.importedMessages += 1

                for part in message.parts {
                    try db.insertMessagePart(
                        id: part.id,
                        messageId: message.id,
                        type: part.type,
                        content: part.content,
                        toolName: part.toolName,
                        toolArgs: part.toolArgs,
                        toolResult: part.toolResult,
                        toolCallId: part.toolCallId,
                        sequenceOrder: part.sequenceOrder
                    )
                }
            }
        }

        for entry in bundle.requestHistory {
            try db.recordRequestHistory(sessionId: entry.sessionId, type: entry.type, payload: entry.payload)
            summary.importedRequestHistoryEntries += 1
        }

        return summary
    }
}
