import Foundation

/// Search logic backed by SQLite FTS5 full-text search
/// Falls back gracefully to simple title matching when FTS is not available
enum SearchPaletteLogic {
    private static let db = DatabaseManager.shared
    
    /// Экранировать строку для безопасной интерполяции в SQL
    private static func sqlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
    
    /// Search sessions using FTS5, fallback to title match
    static func matchingSessions(_ sessions: [ChatSession], query: String) -> [ChatSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sessions }
        
        // Try FTS5 full-text search first
        let ftsSessionIDs = executeFTS5Search(query: trimmed)

        if !ftsSessionIDs.isEmpty {
            // Rank by FTS relevance + filter to our session pool
            // Use Dictionary grouping to avoid crash on duplicate IDs
            let sessionMap = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ranked = ftsSessionIDs.compactMap { sessionMap[$0] }
            // Audit 2026-09-08 (pre-existing test failure): FTS runs against
            // the GLOBAL database, the pool may be a synthetic subset — when
            // the FTS hits live outside the pool, fall back to title matching
            // instead of returning an empty result.
            if !ranked.isEmpty { return ranked }
        }
        
        // Fallback: simple title match
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
    
    /// Search within a specific session's messages
    static func searchWithinSession(sessionId: String, query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // Use FTS5 for message content search
        do {
            let ftsQuery = escapeFTSQuery(trimmed)
            let safeSessionId = sqlEscape(sessionId)
            let safeFtsQuery = sqlEscape(ftsQuery)
            let sql = """
                SELECT m.id FROM messages m
                JOIN messages_fts fts ON m.rowid = fts.rowid
                WHERE m.session_id = '\(safeSessionId)' AND messages_fts MATCH '\(safeFtsQuery)'
                ORDER BY rank
                LIMIT 50
            """
            let results = try db.query(sql)
            return results.compactMap { $0.first as? String }
        } catch {
            print("FTS5 search within session failed: \(error)")
            return []
        }
    }
    
    /// Escape FTS5 special characters and format as phrase search
    private static func escapeFTSQuery(_ query: String) -> String {
        // FTS5 special chars: ^, *, +, -, AND, OR, NOT, (, ), ", :
        // Wrap entire query in quotes for phrase matching to avoid operator interpretation
        let escaped = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .trimmingCharacters(in: .whitespaces)
        
        // Use double-quoted phrase search to prevent - and other operators
        return "\"\(escaped)\""
    }
    
    /// Execute FTS5 search and return matching session IDs
    private static func executeFTS5Search(query: String) -> [String] {
        do {
            let escaped = escapeFTSQuery(query)
            let safeEscaped = sqlEscape(escaped)
            let sql = """
                SELECT DISTINCT m.session_id FROM messages m
                INNER JOIN messages_fts fts ON m.rowid = fts.rowid
                WHERE messages_fts MATCH '\(safeEscaped)'
                ORDER BY rank
                LIMIT 100
            """
            let results = try db.query(sql)
            return results.compactMap { $0.first as? String }
        } catch {
            print("FTS5 search failed: \(error)")
            return []
        }
    }
}
