import Foundation

/// Result of one `ensureIndexed` pass. `unchanged` is what makes the index
/// incremental observable: a second call with the same file records parses
/// nothing.
struct CodeIndexSummary: Equatable, Sendable {
    let parsed: Int
    let unchanged: Int
    let stale: Int
    let counts: CodeIndexCounts
}

struct CodeNeighbor: Equatable, Sendable {
    let edge: CodeEdgeKind
    /// true — the hit points at this node; false — this node points at the hit.
    let isOutgoing: Bool
    let confidence: CodeEdgeConfidence
    let path: String
    /// "func" | "type" | "var" | "file"
    let kind: String
    let name: String
    let startLine: Int?
    let endLine: Int?
}

struct CodeSearchHit: Equatable, Sendable {
    let symbol: CodeSymbol
    let neighbors: [CodeNeighbor]
}

struct CodeSymbolBody: Equatable, Sendable {
    let symbol: CodeSymbol
    /// The exact lines, each prefixed with its 1-based number and a tab.
    let text: String
    /// The on-disk hash that was checked before any line was returned.
    let verifiedHash: String
}

/// Orchestrates the graph: incremental indexing from the project file index,
/// search with graph neighbors, and `read_symbol` whose line numbers are
/// verified against the file on disk before they are shown.
enum CodeIndexService {

    static let maxNeighborsPerHit = 4

    // MARK: - Indexing

    /// Indexes the project from its persisted file index (scanning once when
    /// the project has never been indexed).
    @discardableResult
    static func ensureIndexed(projectPath: String) throws -> CodeIndexSummary {
        let records = PointContextIndexLogic.records(projectPath: projectPath)
        return try ensureIndexed(projectPath: projectPath, records: records)
    }

    @discardableResult
    static func ensureIndexed(projectPath: String,
                              records: [FileIndexRecord]) throws -> CodeIndexSummary {
        let store = try CodeIndexStore.open(projectPath: projectPath)
        return try index(store: store, projectPath: projectPath, records: records)
    }

    private static func index(store: CodeIndexStore,
                              projectPath: String,
                              records: [FileIndexRecord]) throws -> CodeIndexSummary {
        let existing = try store.fileStates()
        var parsed = 0
        var unchanged = 0
        var stalePaths: [String] = []
        var seen = Set<String>()

        for record in records.sorted(by: { $0.path < $1.path }) {
            // Binary/unreadable files cannot produce symbols. If one used to
            // be indexed, mark it stale instead of leaving old line numbers.
            guard let recordedText = record.searchableText, !recordedText.isEmpty else {
                if existing[record.path] != nil, !stalePaths.contains(record.path) {
                    stalePaths.append(record.path)
                }
                continue
            }
            seen.insert(record.path)

            if let state = existing[record.path], !state.isStale,
               state.hash == record.hash, state.size == record.size {
                unchanged += 1
                if state.mtime != record.lastModified {
                    // Same bytes, new timestamp: refresh without re-parsing.
                    try store.touch(path: record.path, mtime: record.lastModified)
                }
                continue
            }

            // The persisted file index can lag behind the disk (the watcher
            // runs asynchronously). When a file has to be parsed anyway, read
            // the real bytes so the stored hash matches what `read_symbol`
            // will verify — otherwise a stale snapshot would resurrect old
            // line numbers on every re-index.
            let disk = diskContent(projectPath: projectPath, path: record.path)
            let text = disk?.text ?? recordedText
            let hash = disk?.hash ?? record.hash
            let size = disk?.size ?? record.size
            let mtime = disk?.mtime ?? record.lastModified

            let extraction = CodeIndexExtractor.extract(
                path: record.path,
                text: text,
                language: record.language
            )
            try store.write(extraction, hash: hash, size: size, mtime: mtime)
            parsed += 1
        }

        for (path, state) in existing where !state.isStale && !seen.contains(path) {
            if !stalePaths.contains(path) { stalePaths.append(path) }
        }
        try store.markStale(paths: stalePaths)

        let before = try store.counts()
        if parsed > 0 || !stalePaths.isEmpty || before.edges == 0 {
            let active = try store.allActiveExtractions()
            // Unresolved candidates never enter the database, so they cannot
            // leak into search, neighbors or evidence.
            let edges = CodeGraphBuilder.build(files: active)
                .filter { $0.confidence != .unresolved }
            try store.replaceEdges(edges)
        }

        return CodeIndexSummary(
            parsed: parsed,
            unchanged: unchanged,
            stale: stalePaths.count,
            counts: try store.counts()
        )
    }

    /// Current on-disk bytes for a file the graph is about to parse. Returns
    /// nil for unsafe paths, binaries and files over the indexing cap, so the
    /// caller falls back to the persisted snapshot.
    private static func diskContent(projectPath: String,
                                    path: String) -> (text: String, hash: String, size: Int, mtime: Double)? {
        guard !projectPath.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else { return nil }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url),
              data.count <= ProjectFileIndexLogic.defaultMaxFileSize,
              !data.contains(0) else { return nil }
        let prefix = data.prefix(ProjectFileIndexLogic.defaultSearchableTextMaxBytes)
        guard let text = String(data: prefix, encoding: .utf8) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return (text, ProjectFileScanner.hash(of: data), data.count, mtime)
    }

    // MARK: - Search

    static func search(projectPath: String,
                       query: String,
                       limit: Int = 8,
                       records: [FileIndexRecord]? = nil) throws -> [CodeSearchHit] {
        let store = try CodeIndexStore.open(projectPath: projectPath)
        let fileRecords = records ?? PointContextIndexLogic.records(projectPath: projectPath)
        _ = try index(store: store, projectPath: projectPath, records: fileRecords)

        let symbols = try store.search(query: query, limit: limit)
        guard !symbols.isEmpty else { return [] }

        let ids = symbols.map(\.id)
        let edges = try store.edges(touching: ids)
        let otherIDs = Array(Set(edges.flatMap { [$0.from, $0.to] }).subtracting(ids))
        // A neighbor may itself be one of the hits (`reload` calls `load` and
        // both are returned by the same query). Those symbols are already
        // loaded, so they must be added to the lookup instead of being
        // subtracted away — otherwise the graph silently hides the strongest
        // relation between two hits.
        var known = try store.symbols(ids: otherIDs)
        for symbol in symbols { known[symbol.id] = symbol }

        return symbols.map { symbol in
            var neighbors: [CodeNeighbor] = []
            for edge in edges where edge.from == symbol.id || edge.to == symbol.id {
                let isOutgoing = edge.from == symbol.id
                let otherID = isOutgoing ? edge.to : edge.from
                if let other = known[otherID] {
                    neighbors.append(CodeNeighbor(
                        edge: edge.kind,
                        isOutgoing: isOutgoing,
                        confidence: edge.confidence,
                        path: other.path,
                        kind: other.kind,
                        name: other.name,
                        startLine: other.startLine,
                        endLine: other.endLine
                    ))
                } else if let path = CodeNode.filePath(of: otherID) {
                    neighbors.append(CodeNeighbor(
                        edge: edge.kind,
                        isOutgoing: isOutgoing,
                        confidence: edge.confidence,
                        path: path,
                        kind: "file",
                        name: (path as NSString).lastPathComponent,
                        startLine: nil,
                        endLine: nil
                    ))
                }
            }
            neighbors.sort {
                let left = neighborPriority($0)
                let right = neighborPriority($1)
                if left != right { return left < right }
                if $0.path != $1.path { return $0.path < $1.path }
                return ($0.startLine ?? 0) < ($1.startLine ?? 0)
            }
            return CodeSearchHit(
                symbol: symbol,
                neighbors: Array(neighbors.prefix(maxNeighborsPerHit))
            )
        }
    }

    /// What a reader needs first: who uses this symbol, where it is declared,
    /// what contains it, what it calls, what tests it. Alphabetical edge order
    /// would put `calls` before `declares` by accident, not by usefulness.
    private static func neighborPriority(_ neighbor: CodeNeighbor) -> Int {
        switch (neighbor.edge, neighbor.isOutgoing) {
        case (.calls, false): return 0
        case (.declares, _): return 1
        case (.contains, _): return 2
        case (.calls, true): return 3
        case (.tests, _): return 4
        case (.imports, _): return 5
        }
    }

    // MARK: - Read symbol

    /// Returns the exact body that was indexed. The on-disk hash is checked
    /// first: if the file changed, no potentially wrong line numbers are
    /// returned — the file is marked stale and the caller must search again.
    static func readSymbol(projectPath: String, id: String) throws -> CodeSymbolBody {
        let store = try CodeIndexStore.open(projectPath: projectPath)
        guard let state = try store.fileStateForSymbol(id: id) else {
            throw CodeIndexError.missingSymbol(id)
        }
        return try read(store: store, projectPath: projectPath, symbol: state.0, state: state.1)
    }

    /// `read_symbol` also accepts path + name, because a model may remember a
    /// file from a previous turn instead of the opaque id.
    static func readSymbol(projectPath: String,
                           path: String,
                           name: String,
                           line: Int? = nil) throws -> CodeSymbolBody {
        let store = try CodeIndexStore.open(projectPath: projectPath)
        _ = try index(store: store, projectPath: projectPath, records: PointContextIndexLogic.records(projectPath: projectPath))
        let symbols = try store.symbols(path: path)
        let named = symbols.filter { $0.name == name || $0.name.lowercased() == name.lowercased() }
        guard !named.isEmpty else { throw CodeIndexError.missingSymbol("\(path)#\(name)") }
        let symbol: CodeSymbol
        if let line {
            symbol = named.min {
                abs($0.startLine - line) < abs($1.startLine - line)
            } ?? named[0]
        } else if named.count == 1 {
            symbol = named[0]
        } else {
            // Several declarations with the same name: pick the first and let
            // the caller see its exact range instead of guessing silently.
            symbol = named[0]
        }
        guard let state = try store.fileState(path: symbol.path) else {
            throw CodeIndexError.missingSymbol("\(path)#\(name)")
        }
        return try read(store: store, projectPath: projectPath, symbol: symbol, state: state)
    }

    private static func read(store: CodeIndexStore,
                             projectPath: String,
                             symbol: CodeSymbol,
                             state: CodeIndexFileState) throws -> CodeSymbolBody {
        guard !state.isStale else { throw CodeIndexError.staleFile(symbol.path) }
        guard !symbol.path.hasPrefix("/"),
              !symbol.path.split(separator: "/").contains("..") else {
            throw CodeIndexError.staleFile(symbol.path)
        }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(symbol.path)
        guard let data = try? Data(contentsOf: url) else {
            try? store.markStale(paths: [symbol.path])
            throw CodeIndexError.staleFile(symbol.path)
        }
        let hash = ProjectFileScanner.hash(of: data)
        guard hash == state.hash else {
            try? store.markStale(paths: [symbol.path])
            throw CodeIndexError.staleFile(symbol.path)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodeIndexError.unreadableFile(symbol.path)
        }
        let lines = text.components(separatedBy: "\n")
        guard symbol.startLine >= 1, symbol.startLine <= lines.count else {
            try? store.markStale(paths: [symbol.path])
            throw CodeIndexError.staleFile(symbol.path)
        }
        let end = min(max(symbol.endLine, symbol.startLine), lines.count)
        let body = (symbol.startLine...end)
            .map { "\($0)\t\(lines[$0 - 1])" }
            .joined(separator: "\n")
        return CodeSymbolBody(symbol: symbol, text: body, verifiedHash: hash)
    }

    // MARK: - Text for the model

    static func renderSearch(query: String, hits: [CodeSearchHit]) -> String {
        guard !hits.isEmpty else {
            return "code_search \"\(query)\": no indexed symbol matched"
        }
        var lines = ["code_search \"\(query)\": \(hits.count) match(es)"]
        for (index, hit) in hits.enumerated() {
            let symbol = hit.symbol
            lines.append("\(index + 1). \(symbol.path):\(symbol.startLine)-\(symbol.endLine) \(symbol.kind) \(symbol.name)")
            lines.append("   id: \(symbol.id)")
            for neighbor in hit.neighbors {
                let arrow = neighbor.isOutgoing ? "->" : "<-"
                let range = neighbor.startLine.map { ":\($0)-\(neighbor.endLine ?? $0)" } ?? ""
                let label = neighbor.kind == "file"
                    ? "\(neighbor.path) (file)"
                    : "\(neighbor.path)\(range) \(neighbor.kind) \(neighbor.name)"
                lines.append("   \(neighbor.edge.rawValue) \(arrow) \(label) [\(neighbor.confidence.rawValue)]")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func renderSymbol(_ body: CodeSymbolBody) -> String {
        let symbol = body.symbol
        return """
        \(symbol.id) (\(symbol.path):\(symbol.startLine)-\(symbol.endLine), hash verified)
        \(body.text)
        """
    }
}
