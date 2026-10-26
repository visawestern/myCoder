import Foundation

/// One memory observation (Phase 5, local-first, no Jev).
/// Persistence (SQLite table, /remember) is a documented follow-up;
/// scoring and selection live here so they are testable without storage.
struct MemoryChunk: Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
    let updatedAt: Date
    let relatedFiles: [String]
    let useCount: Int

    init(id: String, title: String, body: String,
         updatedAt: Date = Date(), relatedFiles: [String] = [], useCount: Int = 0) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
        self.relatedFiles = relatedFiles
        self.useCount = max(0, useCount)
    }
}

/// Pure relevance scoring for memory injection (harness-tax technique:
/// inject top-k by score under a byte budget, never the whole store).
/// Weights: term overlap 0.70 + recency 0.15 + file proximity 0.10 + use 0.05.
/// A fresh chunk with zero overlap scores 0.15 — under the 0.2 noise gate.
enum MemoryScorer {
    /// ~4 bytes per token for budget→bytes conversion (conservative).
    static let bytesPerToken = 4

    static func tokens(of text: String) -> Set<String> {
        let lower = text.lowercased()
        var terms = Set<String>()
        var current = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                if current.count >= 3 { terms.insert(current) }
                current = ""
            }
        }
        if current.count >= 3 { terms.insert(current) }
        return terms
    }

    static func score(query: String, openFiles: [String] = [],
                      chunk: MemoryChunk, now: Date = Date()) -> Double {
        let q = tokens(of: query)
        let c = tokens(of: chunk.title + " " + chunk.body)
        let overlap: Double
        if q.isEmpty {
            overlap = 0
        } else {
            overlap = Double(q.intersection(c).count) / Double(q.count)
        }
        let days = max(0, now.timeIntervalSince(chunk.updatedAt) / 86400)
        let recency = exp(-days / 30.0)
        let open = Set(openFiles)
        let proximity: Double = open.isEmpty ? 0
            : (chunk.relatedFiles.contains { open.contains($0) } ? 1 : 0)
        let use = min(1.0, Double(chunk.useCount) / 5.0)
        return 0.70 * overlap + 0.15 * recency + 0.10 * proximity + 0.05 * use
    }

    /// Top chunks by score above `threshold`, greedily filling
    /// `budgetTokens * bytesPerToken`. Ties break newer-first, then by id.
    static func selectTop(query: String, chunks: [MemoryChunk], now: Date = Date(),
                          openFiles: [String] = [],
                          budgetTokens: Int, threshold: Double) -> [MemoryChunk] {
        let scored = chunks.map { ($0, score(query: query, openFiles: openFiles, chunk: $0, now: now)) }
            .filter { $0.1 >= threshold }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.updatedAt != $1.0.updatedAt { return $0.0.updatedAt > $1.0.updatedAt }
                return $0.0.id < $1.0.id
            }
        let budget = max(0, budgetTokens * bytesPerToken)
        var used = 0
        var out: [MemoryChunk] = []
        for (chunk, _) in scored {
            let size = chunk.body.utf8.count
            guard used + size <= budget else { continue }
            used += size
            out.append(chunk)
        }
        return out
    }
}
