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

            var best = 0.0
            var matched: [SymbolDeclaration] = []
            for term in terms {
                for symbol in entry.symbols {
                    let name = symbol.name.lowercased()
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
                if baseName == term {
                    best = max(best, 80)
                } else if lowerPath.contains(term) {
                    best = max(best, 30)
                }
                if entry.searchTokens.contains(term) {
                    best = max(best, 20)
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
