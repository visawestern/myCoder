import Foundation

/// One ranked file the compiler may pull code from. This is a *candidate*, not
/// a prompt: the compiler decides how much of it fits the budget.
struct ContextCandidate: Equatable, Identifiable {
    let path: String
    let language: String
    let score: Double
    let lastModified: TimeInterval
    /// Upper bound of what this file would add to the context (its index size).
    let estimatedBytes: Int
    /// Symbols that matched the query, with their real line numbers.
    let matchedSymbols: [SymbolDeclaration]

    var id: String { path }
}

/// Ranks project files for a user query instead of sending the whole board to
/// a model. Deterministic: the same board and query always give the same order.
enum CandidateRanker {

    /// A file this large is not a code excerpt; reading it would blow the
    /// context and the memory budget.
    static let maxCandidateFileBytes = 2 * 1024 * 1024

    static func rank(board: ContextBoard,
                     query: String,
                     limit: Int = 20,
                     budgetBytes: Int = 12_000) -> [ContextCandidate] {
        guard limit > 0, budgetBytes > 0 else { return [] }
        let terms = queryTerms(query)
        guard !terms.isEmpty else { return [] }

        struct Scored {
            let entry: ContextBoardEntry
            let score: Double
            let matched: [SymbolDeclaration]
        }

        var scored: [Scored] = []
        for entry in board.entries {
            guard entry.size <= maxCandidateFileBytes else { continue }
            let lowerPath = entry.path.lowercased()
            let baseName = (entry.path as NSString).lastPathComponent
                .replacingOccurrences(of: ".\(entry.language)", with: "")
                .lowercased()

            // Hot path (live run 2026-11-04, chats 77DF9308/FF5D0A17): the old
            // loop lowercased every symbol name once per TERM — 2 000 files ×
            // 60 symbols × 4 terms = 480 000 String allocations in one rank
            // call, the single hottest frame of the stalled send. Now every
            // name is lowercased once per ENTRY, and terms are prefiltred
            // against one joined blob: a term that occurs nowhere in the blob
            // cannot match any single name (terms never contain "\n"), so the
            // per-symbol walk runs only for entries that mention the term.
            let lowerNames = entry.symbols.map { lowercasedFast($0.name) }
            let namesBlob = lowerNames.joined(separator: "\n")

            var best = 0.0
            var matched: [SymbolDeclaration] = []
            for term in terms {
                if baseName == term {
                    best = max(best, 80)
                } else if lowerPath.contains(term) {
                    best = max(best, 30)
                }
                if entry.searchTokens.contains(term) {
                    best = max(best, 20)
                }
                guard namesBlob.contains(term) else { continue }
                for (index, name) in lowerNames.enumerated() {
                    let symbol = entry.symbols[index]
                    if name == term {
                        best = max(best, 100)
                        matched.append(symbol)
                    } else if name.hasPrefix(term) {
                        best = max(best, 60)
                        matched.append(symbol)
                    } else if name.contains(term) {
                        best = max(best, 40)
                        matched.append(symbol)
                    }
                }
            }
            guard best > 0 else { continue }
            // Recent files win ties; the bonus is deliberately tiny so it can
            // never outrank a real symbol match.
            let recency = min(max(entry.lastModified, 0) / 1e11, 0.9)
            scored.append(Scored(entry: entry, score: best + recency, matched: matched))
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.entry.lastModified != $1.entry.lastModified {
                return $0.entry.lastModified > $1.entry.lastModified
            }
            return $0.entry.path < $1.entry.path
        }

        var result: [ContextCandidate] = []
        var used = 0
        for item in scored {
            guard result.count < limit else { break }
            guard used + item.entry.size <= budgetBytes else { continue }
            used += item.entry.size
            result.append(ContextCandidate(
                path: item.entry.path,
                language: item.entry.language,
                score: item.score,
                lastModified: item.entry.lastModified,
                estimatedBytes: item.entry.size,
                matchedSymbols: item.matched
            ))
        }
        return result
    }

    /// ASCII fast path for the per-symbol lowercase: identical to
    /// `lowercased()` for pure-ASCII strings (source identifiers), with a
    /// Foundation fallback for anything else. This keeps exact ranking
    /// semantics while removing the allocation storm from the hot loop.
    private static func lowercasedFast(_ name: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(name.utf8.count)
        var isASCII = true
        for byte in name.utf8 {
            if byte >= 128 {
                isASCII = false
                break
            }
            bytes.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        }
        guard isASCII else { return name.lowercased() }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Splits the query into lowercase terms, dropping punctuation and
    /// boilerplate words that would match every file.
    static func queryTerms(_ query: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "this", "that", "как", "что", "где",
            "для", "или", "это", "все", "мне", "надо", "нужно", "please"
        ]
        var terms: [String] = []
        var seen = Set<String>()
        var current = ""
        for scalar in query.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                if current.count >= 3, !stopWords.contains(current), seen.insert(current).inserted {
                    terms.append(current)
                }
                current = ""
            }
        }
        if current.count >= 3, !stopWords.contains(current), seen.insert(current).inserted {
            terms.append(current)
        }
        return terms
    }
}
