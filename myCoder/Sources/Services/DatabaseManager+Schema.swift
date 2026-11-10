import Foundation
import SQLite

extension DatabaseManager {
    // MARK: - Table Creation
    
    func createTables() throws {
        guard let db = db else { return }
        
        // Projects table
        try db.run(projects.create(ifNotExists: true) { t in
            t.column(projectId, primaryKey: true)
            t.column(projectName)
            t.column(projectPath, unique: true)
            t.column(projectCreatedAt)
            t.column(projectLastOpenedAt)
            t.column(projectGitRemote)
            t.column(projectGitBranch)
            t.column(projectIsPinned, defaultValue: false)
            t.column(projectColor)
            t.column(projectIcon)
            t.column(projectMetadata)
            t.column(projectDefaultAccessLevel)
            t.column(projectCustomInstructions)
            t.column(projectEnvVars)
            t.column(projectStableId)
            t.column(projectArchivedAt)
            t.column(projectDefaultProviderId)
            t.column(projectDefaultModelId)
        })
        
        // Sessions table
        try db.run(sessions.create(ifNotExists: true) { t in
            t.column(sessionId, primaryKey: true)
            t.column(sessionProjectId)
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
            t.column(sessionDraftText)
            t.foreignKey(sessionProjectId, references: projects, projectId)
        })
        
        // Session routes table
        try db.run(sessionRoutes.create(ifNotExists: true) { t in
            t.column(sessionRouteSessionId, primaryKey: true)
            t.column(sessionRouteProjectPath)
            t.column(sessionRouteUpdatedAt)
        })
        
        // Messages table
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
        
        // Message Parts table
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
        
        // Tool Calls table
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
        
        // File Changes table
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
        
        // Undo Stack table
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
        
        // Providers table
        try db.run(providers.create(ifNotExists: true) { t in
            t.column(providerId, primaryKey: true)
            t.column(providerName)
            t.column(providerType)
            t.column(providerApiKeyKeychainId)
            t.column(providerBaseUrl)
            t.column(providerIsEnabled, defaultValue: true)
            t.column(providerSupportsToolcall, defaultValue: true)
            t.column(providerSupportsAcp, defaultValue: false)
            t.column(providerIsOnline, defaultValue: false)
            t.column(providerLastHealthCheck)
            t.column(providerCreatedAt)
            t.column(providerMetadata)
        })
    }
    
    // MARK: - Index Creation
    
    func createIndexes() throws {
        guard let db = db else { return }
        
        // Projects indexes
        try db.run(projects.createIndex(projectLastOpenedAt, ifNotExists: true))
        try db.run(projects.createIndex(projectIsPinned, ifNotExists: true))
        
        // Sessions indexes
        try db.run(sessions.createIndex(sessionProjectId, ifNotExists: true))
        try db.run(sessions.createIndex(sessionUpdatedAt, ifNotExists: true))
        try db.run(sessions.createIndex(sessionIsArchived, ifNotExists: true))
        try db.run(sessions.createIndex([sessionProjectId, sessionUpdatedAt], ifNotExists: true))
        
        // Messages indexes
        try db.run(messages.createIndex(messageSessionId, ifNotExists: true))
        try db.run(messages.createIndex(messageCreatedAt, ifNotExists: true))
        try db.run(messages.createIndex([messageSessionId, messageCreatedAt], ifNotExists: true))
        
        // Message Parts indexes
        try db.run(messageParts.createIndex(partMessageId, ifNotExists: true))
        try db.run(messageParts.createIndex([partMessageId, partSequenceOrder], ifNotExists: true))
        
        // Tool Calls indexes
        try db.run(toolCalls.createIndex(toolCallMessageId, ifNotExists: true))
        try db.run(toolCalls.createIndex(toolCallStatus, ifNotExists: true))
        try db.run(toolCalls.createIndex(toolCallName, ifNotExists: true))
        
        // File Changes indexes
        try db.run(fileChanges.createIndex(fileChangeToolCallId, ifNotExists: true))
        try db.run(fileChanges.createIndex(fileChangePath, ifNotExists: true))
        try db.run(fileChanges.createIndex(fileChangeTimestamp, ifNotExists: true))
        
        // Undo Stack indexes
        try db.run(undoStack.createIndex(undoSessionId, ifNotExists: true))
        try db.run(undoStack.createIndex([undoSessionId, undoCreatedAt], ifNotExists: true))
    }
    
    // MARK: - FTS5 Full-Text Search
    
    func createFTS5Index() throws {
        guard let db = db else { return }
        
        // Standalone FTS5 table (no external content mapping to avoid column mismatch issues)
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                content,
                session_title,
                file_paths,
                tool_names
            );
        """)
        
        // Triggers for auto-sync FTS5 index with messages table
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
}
