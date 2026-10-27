import Foundation

/// One durable fact about the project, written by the user and reused as
/// evidence on later turns. Memory is not a chat summary: it is a small,
/// inspectable list with a source, so a stale entry can be found and removed.
struct ProjectMemoryChunk: Equatable, Sendable {
    /// Stable hash of the normalized text: remembering the same fact twice
    /// updates the entry instead of duplicating it.
    let id: String
    let projectID: String
    let kind: String
    var text: String
    /// Project-relative files the fact is about.
    var files: [String]
    /// Lowercased identifiers the fact mentions (entities/tags).
    var tags: [String]
    /// The chat message this came from, when it did.
    var sourceMessageID: String?
    let createdAt: Int64
    var updatedAt: Int64
}

enum ProjectMemoryExtraction {

    static let kinds = ["fact", "decision", "preference", "task"]

    /// Turns `/remember <text>` into a chunk. Returns nil for empty input —
    /// an empty command must not create an empty memory.
    static func chunk(text: String,
                      projectPath: String,
                      files: [String] = [],
                      sourceMessageID: String? = nil,
                      now: Int64 = Int64(Date().timeIntervalSince1970),
                      fileManager: FileManager = .default) -> ProjectMemoryChunk? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let plan = ContextQueryPlanner.plan(for: trimmed)
        var detectedFiles: [String] = []
        for path in files + plan.files {
            guard isSafeProjectPath(path, projectPath: projectPath, fileManager: fileManager) else { continue }
            if !detectedFiles.contains(path) { detectedFiles.append(path) }
        }

        var tags: [String] = []
        for symbol in plan.symbols {
            let lower = symbol.lowercased()
            if !tags.contains(lower) { tags.append(lower) }
        }

        return ProjectMemoryChunk(
            id: stableID(for: trimmed),
            projectID: projectPath,
            kind: kind(for: trimmed),
            text: trimmed,
            files: detectedFiles,
            tags: tags,
            sourceMessageID: sourceMessageID,
            createdAt: now,
            updatedAt: now
        )
    }

    /// `decision:` / `предпочтение:` style prefixes let the user say what kind
    /// of fact this is without a separate flag.
    static func kind(for text: String) -> String {
        let lower = text.lowercased()
        if lower.hasPrefix("decision") || lower.hasPrefix("решение") { return "decision" }
        if lower.hasPrefix("preference") || lower.hasPrefix("предпочт") { return "preference" }
        if lower.hasPrefix("todo") || lower.hasPrefix("task") || lower.hasPrefix("задач") { return "task" }
        return "fact"
    }

    static func stableID(for text: String) -> String {
        let normalized = text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return "mem_" + String(hash, radix: 16)
    }

    /// A memory may only point at files inside the project; a path from the
    /// text is not trusted (`../`, absolute paths, missing files are dropped).
    private static func isSafeProjectPath(_ path: String,
                                          projectPath: String,
                                          fileManager: FileManager) -> Bool {
        guard !projectPath.isEmpty, !path.isEmpty, !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else { return false }
        let root = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return false
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }
}

/// Ranks stored memories for a message. Deterministic: score, then recency,
/// then id — the same memory list and message always give the same order.
enum ProjectMemoryRanker {

    static func rank(_ chunks: [ProjectMemoryChunk],
                     query: String,
                     limit: Int = 5) -> [ProjectMemoryChunk] {
        guard limit > 0 else { return [] }
        let plan = ContextQueryPlanner.plan(for: query)
        var terms = plan.terms
        for symbol in plan.symbols {
            let lower = symbol.lowercased()
            if !terms.contains(lower) { terms.append(lower) }
        }
        guard !terms.isEmpty else { return [] }

        var scored: [(chunk: ProjectMemoryChunk, score: Double)] = []
        for chunk in chunks {
            var score = 0.0
            let lowerText = chunk.text.lowercased()
            for term in terms {
                if chunk.tags.contains(term) {
                    score += 100
                } else if chunk.tags.contains(where: { $0.hasPrefix(term) }) {
                    score += 60
                }
                if chunk.files.contains(where: { $0.lowercased().contains(term) }) {
                    score += 30
                }
                if lowerText.contains(term) {
                    score += 20
                }
            }
            // An exact kind word in the message ("decision") is a weak signal.
            if terms.contains(chunk.kind) { score += 10 }
            guard score > 0 else { continue }
            scored.append((chunk, score))
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.chunk.updatedAt != $1.chunk.updatedAt {
                return $0.chunk.updatedAt > $1.chunk.updatedAt
            }
            return $0.chunk.id < $1.chunk.id
        }
        return scored.prefix(limit).map(\.chunk)
    }
}
