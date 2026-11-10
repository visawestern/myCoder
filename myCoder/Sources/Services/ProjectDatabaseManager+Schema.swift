import Foundation
import SQLite

extension ProjectDatabaseManager {
    // MARK: - Schema

    func createSchema() throws {
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
    func createSpecSchema() throws {
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

    func addColumnIfMissing(table: String, column: String, definition: String) throws {
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

    func createFTS5Index() throws {
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
}
