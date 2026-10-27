import Foundation
import SQLite

/// One row of `code_files`: what the index currently believes about a file.
struct CodeIndexFileState: Equatable, Sendable {
    let path: String
    let language: String
    let hash: String
    let size: Int
    let mtime: Double
    let isStale: Bool
}

struct CodeIndexCounts: Equatable, Sendable {
    let files: Int
    let staleFiles: Int
    let symbols: Int
    let edges: Int
}

enum CodeIndexError: LocalizedError {
    case noProject
    case corruptRow(String)
    case missingSymbol(String)
    case staleFile(String)
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "The code index needs a project path"
        case .corruptRow(let path):
            return "The code index row for \(path) is corrupt; re-index the project"
        case .missingSymbol(let id):
            return "No indexed symbol matches \(id)"
        case .staleFile(let path):
            return "\(path) changed or disappeared after indexing; search again before reading it"
        case .unreadableFile(let path):
            return "\(path) is not readable UTF-8 text"
        }
    }
}

/// The code graph lives in its own database (`.mycoder/code_index.sqlite`),
/// never in `project.db`: a failed or slow graph rebuild must not touch the
/// session/memory/spec data, and the graph can be deleted to force a re-index
/// without losing anything the user wrote.
struct CodeIndexStore {
    let db: Connection

    static func databaseURL(projectPath: String) -> URL {
        ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
            .appendingPathComponent("code_index.sqlite")
    }

    static func open(projectPath: String) throws -> CodeIndexStore {
        guard !projectPath.isEmpty else { throw CodeIndexError.noProject }
        let directory = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = try Connection(databaseURL(projectPath: projectPath).path)
        connection.busyTimeout = 5.0
        try connection.execute("PRAGMA journal_mode=WAL")
        try createSchema(connection)
        return CodeIndexStore(db: connection)
    }

    /// Every statement is idempotent, so an existing graph database gains new
    /// columns/tables on the next open instead of requiring a migration.
    static func createSchema(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS code_files (
                path TEXT PRIMARY KEY,
                language TEXT NOT NULL,
                hash TEXT NOT NULL,
                size INTEGER NOT NULL,
                mtime REAL NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                extraction_json TEXT NOT NULL
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS code_symbols (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                name_lower TEXT NOT NULL,
                kind TEXT NOT NULL,
                start_line INTEGER NOT NULL,
                end_line INTEGER NOT NULL
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS code_symbols_name ON code_symbols(name_lower)")
        try db.execute("CREATE INDEX IF NOT EXISTS code_symbols_path ON code_symbols(path)")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS code_edges (
                from_id TEXT NOT NULL,
                to_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                confidence TEXT NOT NULL,
                PRIMARY KEY (from_id, to_id, kind)
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS code_edges_to ON code_edges(to_id)")
    }

    // MARK: - Files

    func fileStates() throws -> [String: CodeIndexFileState] {
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            "SELECT path, language, hash, size, mtime, status FROM code_files"
        ))
        var result: [String: CodeIndexFileState] = [:]
        for row in rows {
            guard let path = row[0] as? String,
                  let language = row[1] as? String,
                  let hash = row[2] as? String,
                  let size = intValue(row[3]),
                  let mtime = doubleValue(row[4]),
                  let status = row[5] as? String else { continue }
            result[path] = CodeIndexFileState(
                path: path,
                language: language,
                hash: hash,
                size: size,
                mtime: mtime,
                isStale: status != "active"
            )
        }
        return result
    }

    func fileState(path: String) throws -> CodeIndexFileState? {
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            "SELECT path, language, hash, size, mtime, status FROM code_files WHERE path = ? LIMIT 1",
            [path]
        ))
        guard let row = rows.first,
              let language = row[1] as? String,
              let hash = row[2] as? String,
              let size = intValue(row[3]),
              let mtime = doubleValue(row[4]),
              let status = row[5] as? String else { return nil }
        return CodeIndexFileState(
            path: path,
            language: language,
            hash: hash,
            size: size,
            mtime: mtime,
            isStale: status != "active"
        )
    }

    /// Replaces one file's symbols and extraction in a single transaction, so
    /// a crash can never leave a half-written file row.
    func write(_ extraction: CodeFileExtraction,
               hash: String,
               size: Int,
               mtime: Double) throws {
        let data = try JSONEncoder().encode(extraction)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CodeIndexError.corruptRow(extraction.path)
        }
        try db.transaction {
            try db.run("DELETE FROM code_symbols WHERE path = ?", [extraction.path])
            let insert = """
                INSERT OR REPLACE INTO code_symbols
                (id, path, name, name_lower, kind, start_line, end_line)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """
            for symbol in extraction.symbols {
                try db.run(insert, [
                    symbol.id,
                    symbol.path,
                    symbol.name,
                    symbol.name.lowercased(),
                    symbol.kind,
                    symbol.startLine,
                    symbol.endLine
                ])
            }
            try db.run("""
                INSERT INTO code_files (path, language, hash, size, mtime, status, extraction_json)
                VALUES (?, ?, ?, ?, ?, 'active', ?)
                ON CONFLICT(path) DO UPDATE SET
                    language = excluded.language,
                    hash = excluded.hash,
                    size = excluded.size,
                    mtime = excluded.mtime,
                    status = 'active',
                    extraction_json = excluded.extraction_json
                """, [extraction.path, extraction.language, hash, size, mtime, json])
        }
    }

    /// Marks files whose content is gone or unreadable. Rows stay so a stale
    /// symbol id still resolves to a row and can answer "this file changed"
    /// instead of "unknown symbol".
    func markStale(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try db.transaction {
            for path in paths {
                try db.run("UPDATE code_files SET status = 'stale' WHERE path = ?", [path])
            }
        }
    }

    /// A file whose content hash is unchanged but whose mtime moved is not
    /// re-parsed; only its timestamp is refreshed.
    func touch(path: String, mtime: Double) throws {
        try db.run("UPDATE code_files SET mtime = ?, status = 'active' WHERE path = ?", [mtime, path])
    }

    func allActiveExtractions() throws -> [CodeFileExtraction] {
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            "SELECT path, extraction_json FROM code_files WHERE status = 'active' ORDER BY path"
        ))
        var result: [CodeFileExtraction] = []
        for row in rows {
            guard let path = row[0] as? String, let json = row[1] as? String else { continue }
            guard let data = json.data(using: .utf8) else {
                throw CodeIndexError.corruptRow(path)
            }
            do {
                result.append(try JSONDecoder().decode(CodeFileExtraction.self, from: data))
            } catch {
                throw CodeIndexError.corruptRow(path)
            }
        }
        return result
    }

    // MARK: - Symbols

    func symbols(path: String) throws -> [CodeSymbol] {
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            """
            SELECT path, name, kind, start_line, end_line
            FROM code_symbols WHERE path = ? ORDER BY start_line, name
            """,
            [path]
        ))
        return rows.compactMap(decodeSymbol)
    }

    func symbol(id: String) throws -> CodeSymbol? {
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            "SELECT path, name, kind, start_line, end_line FROM code_symbols WHERE id = ? LIMIT 1",
            [id]
        ))
        return rows.first.flatMap(decodeSymbol)
    }

    /// Batch lookup for graph neighbors: one query instead of one per edge.
    func symbols(ids: [String]) throws -> [String: CodeSymbol] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try SQLiteSafeQuery.rows(db.prepare(
            """
            SELECT id, path, name, kind, start_line, end_line
            FROM code_symbols WHERE id IN (\(placeholders))
            """,
            ids
        ))
        var result: [String: CodeSymbol] = [:]
        for row in rows {
            guard let id = row[0] as? String,
                  let path = row[1] as? String,
                  let name = row[2] as? String,
                  let kind = row[3] as? String,
                  let start = intValue(row[4]),
                  let end = intValue(row[5]) else { continue }
            result[id] = CodeSymbol(
                path: path,
                name: name,
                kind: kind,
                startLine: start,
                endLine: end
            )
        }
        return result
    }

    /// The symbol row plus the file state it was indexed from, in one call, so
    /// `read_symbol` can check the hash before returning a single line.
    func fileStateForSymbol(id: String) throws -> (CodeSymbol, CodeIndexFileState)? {
        guard let symbol = try symbol(id: id),
              let state = try fileState(path: symbol.path) else { return nil }
        return (symbol, state)
    }

    /// Name search over active files. SQL narrows the candidates; ranking is
    /// done in Swift so it stays deterministic and testable.
    func search(query: String, limit: Int = 8) throws -> [CodeSymbol] {
        let terms = CodeIndexQuery.terms(query)
        guard !terms.isEmpty, limit > 0 else { return [] }
        var seen = Set<String>()
        var candidates: [CodeSymbol] = []
        for term in terms {
            let pattern = "%\(escapeLike(term))%"
            let rows = try SQLiteSafeQuery.rows(db.prepare(
                """
                SELECT s.path, s.name, s.kind, s.start_line, s.end_line
                FROM code_symbols s
                JOIN code_files f ON f.path = s.path
                WHERE f.status = 'active'
                  AND (s.name_lower LIKE ? ESCAPE '\\' OR lower(s.path) LIKE ? ESCAPE '\\')
                LIMIT 200
                """,
                [pattern, pattern]
            ))
            for row in rows {
                guard let symbol = decodeSymbol(row) else { continue }
                guard seen.insert(symbol.id).inserted else { continue }
                candidates.append(symbol)
            }
        }
        return candidates
            .map { (symbol: $0, score: CodeIndexQuery.score($0, terms: terms)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.symbol.path != $1.symbol.path { return $0.symbol.path < $1.symbol.path }
                return $0.symbol.startLine < $1.symbol.startLine
            }
            .prefix(limit)
            .map(\.symbol)
    }

    // MARK: - Edges

    /// Edges touching any of the ids. Unresolved edges are not persisted, and
    /// the flag is kept explicit so a caller cannot accidentally opt into
    /// placeholders that do not exist.
    func edges(touching ids: [String], includeUnresolved: Bool = false) throws -> [CodeEdge] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var sql = """
            SELECT from_id, to_id, kind, confidence FROM code_edges
            WHERE (from_id IN (\(placeholders)) OR to_id IN (\(placeholders)))
            """
        if !includeUnresolved {
            sql += " AND confidence != 'unresolved'"
        }
        let rows = try SQLiteSafeQuery.rows(db.prepare(sql, ids + ids))
        return rows.compactMap { row in
            guard let from = row[0] as? String,
                  let to = row[1] as? String,
                  let kind = (row[2] as? String).flatMap(CodeEdgeKind.init(rawValue:)),
                  let confidence = (row[3] as? String).flatMap(CodeEdgeConfidence.init(rawValue:)) else {
                return nil
            }
            return CodeEdge(from: from, to: to, kind: kind, confidence: confidence)
        }
    }

    func replaceEdges(_ edges: [CodeEdge]) throws {
        try db.transaction {
            try db.run("DELETE FROM code_edges")
            let statement = try db.prepare(
                "INSERT OR REPLACE INTO code_edges (from_id, to_id, kind, confidence) VALUES (?, ?, ?, ?)"
            )
            for edge in edges {
                try statement.run([
                    edge.from,
                    edge.to,
                    edge.kind.rawValue,
                    edge.confidence.rawValue
                ])
            }
        }
    }

    func counts() throws -> CodeIndexCounts {
        let files = try scalarInt("SELECT COUNT(*) FROM code_files")
        let stale = try scalarInt("SELECT COUNT(*) FROM code_files WHERE status = 'stale'")
        let symbols = try scalarInt("SELECT COUNT(*) FROM code_symbols")
        let edges = try scalarInt("SELECT COUNT(*) FROM code_edges")
        return CodeIndexCounts(files: files, staleFiles: stale, symbols: symbols, edges: edges)
    }

    // MARK: - Helpers

    private func scalarInt(_ sql: String) throws -> Int {
        let rows = try SQLiteSafeQuery.rows(db.prepare(sql))
        return rows.first.flatMap { intValue($0.first ?? nil) } ?? 0
    }

    private func decodeSymbol(_ row: [Binding?]) -> CodeSymbol? {
        guard row.count >= 5,
              let path = row[0] as? String,
              let name = row[1] as? String,
              let kind = row[2] as? String,
              let start = intValue(row[3]),
              let end = intValue(row[4]) else { return nil }
        return CodeSymbol(path: path, name: name, kind: kind, startLine: start, endLine: end)
    }

    private func intValue(_ value: Binding?) -> Int? {
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        return nil
    }

    private func doubleValue(_ value: Binding?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    /// Escapes SQL LIKE wildcards so a query for `a_b` cannot match `axb`.
    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

/// Query tokenization and ranking for `code_search`. Kept separate from the
/// store so the ranking can be tested without a database.
enum CodeIndexQuery {

    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "where", "what", "how",
        "как", "что", "где", "для", "или", "это", "все", "мне", "надо", "нужно"
    ]

    static func terms(_ query: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        var current = ""
        for scalar in query.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                append(current, to: &result, seen: &seen)
                current = ""
            }
        }
        append(current, to: &result, seen: &seen)
        return result
    }

    private static func append(_ value: String, to result: inout [String], seen: inout Set<String>) {
        guard value.count >= 2, !stopWords.contains(value), seen.insert(value).inserted else { return }
        result.append(value)
    }

    /// Exact name > name prefix > name contains > path contains. Matched terms
    /// add up, so a query covering both a symbol and its file wins.
    static func score(_ symbol: CodeSymbol, terms: [String]) -> Int {
        let name = symbol.name.lowercased()
        let path = symbol.path.lowercased()
        var score = 0
        for term in terms {
            if name == term { score += 8 }
            else if name.hasPrefix(term) { score += 5 }
            else if name.contains(term) { score += 3 }
            else if path.contains(term) { score += 1 }
        }
        switch symbol.kind {
        case "type": score += 2
        case "func": score += 1
        default: break
        }
        return score
    }
}
