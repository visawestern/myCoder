import Foundation

/// What the turn compiler understood from the user's message. Built from the
/// text alone — no model, no network, same answer every time.
struct ContextQueryPlan: Equatable, Sendable {
    /// Lowercase terms used for ranking.
    let terms: [String]
    /// Identifiers that look like code (`UserStore`, `testLoad`).
    let symbols: [String]
    /// Explicit project-relative paths in the message.
    let files: [String]
    /// Line numbers the user pointed at (`File.swift:42`).
    let lineNumbers: [Int]
}

enum ContextQueryPlanner {

    static func plan(for message: String) -> ContextQueryPlan {
        let files = paths(in: message)
        let lineNumbers = lineNumbers(in: message)
        let symbols = symbols(in: message)
        var terms = CandidateRanker.queryTerms(message)
        for symbol in symbols {
            let lower = symbol.lowercased()
            if !terms.contains(lower) { terms.append(lower) }
        }
        return ContextQueryPlan(terms: terms, symbols: symbols, files: files, lineNumbers: lineNumbers)
    }

    private static func paths(in text: String) -> [String] {
        let pattern = #"([A-Za-z0-9_./\-]+\.[A-Za-z0-9]{1,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              !text.contains("\n#") // cheap guard against huge inputs
        else { return [] }
        let ns = text as NSString
        var result: [String] = []
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range(at: 1))
            // A path must contain a separator or start with a known source
            // prefix; `UserStore.swift` and `testLoad()` are different things.
            if !result.contains(value) { result.append(value) }
        }
        return result
    }

    private static func lineNumbers(in text: String) -> [Int] {
        let pattern = #":(\d{1,6})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var result: [Int] = []
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard let value = Int(ns.substring(with: match.range(at: 1))), !result.contains(value) else { continue }
            result.append(value)
        }
        return result
    }

    private static func symbols(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            guard current.count >= 3 else { current = ""; return }
            let looksLikeCode = current.contains(where: { $0.isUppercase })
                || current.contains("_")
                || current.first?.isLowercase == true && current.dropFirst().contains(where: { $0.isUppercase })
            if looksLikeCode, !result.contains(current) { result.append(current) }
            current = ""
        }
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}

// MARK: - Pack

struct ContextCitation: Equatable, Sendable {
    let path: String
    let startLine: Int
    let endLine: Int
    let symbol: String?
}

struct ContextSection: Equatable, Sendable {
    let title: String
    let body: String
}

struct DroppedSource: Equatable, Sendable {
    let path: String
    let reason: String
}

struct ContextManifest: Equatable, Sendable {
    /// Paths that really made it into the pack, in order.
    let included: [String]
    /// Paths that were considered and left out, with the reason.
    let dropped: [DroppedSource]
    /// How many files were ranked before the budget was applied.
    let considered: Int
}

struct CompiledContextPack: Equatable, Sendable {
    let sections: [ContextSection]
    let citations: [ContextCitation]
    let unknowns: [String]
    let manifest: ContextManifest
    let estimatedTokens: Int
    let text: String
    /// Ids of the stored project memories that made it into the pack.
    let memoryIDs: [String]
}

/// Assembles the context for one user message: plan → candidates → real code
/// blocks → budget → pack. Deterministic by construction (no model, no dates).
enum TurnContextCompiler {

    static let defaultBudgetTokens = 6_000
    /// Rough but stable: four bytes per token. Only used for budgeting, never
    /// shown as a billing number.
    static let bytesPerToken = 4

    static func compile(message: String,
                        board: ContextBoard,
                        projectRoot: String,
                        memories: [ProjectMemoryChunk] = [],
                        budgetTokens: Int = defaultBudgetTokens,
                        maxFiles: Int = 8) -> CompiledContextPack {
        let plan = ContextQueryPlanner.plan(for: message)
        let query = (plan.terms + plan.symbols).joined(separator: " ")
        var candidates = CandidateRanker.rank(
            board: board,
            query: query,
            limit: max(1, maxFiles),
            budgetBytes: Int.max
        )
        // A path the user typed explicitly always comes first.
        let explicit = Set(plan.files)
        if !explicit.isEmpty {
            candidates.sort {
                let left = explicit.contains($0.path) ? 1 : 0
                let right = explicit.contains($1.path) ? 1 : 0
                if left != right { return left > right }
                return $0.score > $1.score
            }
        }

        let budgetBytes = max(0, budgetTokens * bytesPerToken)
        // The request is never shortened: the model must see every word the
        // user typed. The budget applies to the evidence around it.
        let request = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [ContextSection] = [
            ContextSection(title: "Запрос", body: request)
        ]
        var citations: [ContextCitation] = []
        var unknowns: [String] = []
        var included: [String] = []
        var dropped: [DroppedSource] = []

        // Durable facts the user wrote with /remember. They are ranked against
        // the same query as the code, and each line keeps its source, so a
        // stale memory can be traced back and removed.
        let relevantMemories = ProjectMemoryRanker.rank(memories, query: message, limit: 5)
        let memoryIDs = relevantMemories.map(\.id)
        if !relevantMemories.isEmpty {
            let lines = relevantMemories.map { chunk -> String in
                let source: String
                if let messageID = chunk.sourceMessageID, !messageID.isEmpty {
                    source = "сообщение \(messageID)"
                } else {
                    source = "id \(chunk.id)"
                }
                return "- [\(chunk.kind)] \(chunk.text) (источник: \(source))"
            }
            sections.append(ContextSection(title: "Память проекта", body: lines.joined(separator: "\n")))
        }

        if candidates.isEmpty {
            unknowns.append("в индексе проекта нет файлов, подходящих под запрос")
        }

        for candidate in candidates {
            guard let ref = reference(for: candidate, plan: plan) else {
                dropped.append(DroppedSource(path: candidate.path, reason: "не найден подходящий символ"))
                continue
            }
            let block: String
            do {
                block = try ContextMaterializer.block(for: ref, projectRoot: projectRoot)
            } catch let error as LocalCompilerError {
                unknowns.append("\(candidate.path): \(error.errorDescription ?? "не прочитан")")
                dropped.append(DroppedSource(path: candidate.path, reason: "файл не прочитан"))
                continue
            } catch {
                unknowns.append("\(candidate.path): \(error.localizedDescription)")
                dropped.append(DroppedSource(path: candidate.path, reason: "файл не прочитан"))
                continue
            }

            let section = ContextSection(title: candidate.path, body: block)
            let proposed = sections + [section]
            if render(sections: proposed, unknowns: unknowns, dropped: dropped).utf8.count > budgetBytes {
                dropped.append(DroppedSource(
                    path: candidate.path,
                    reason: "не влезает в бюджет \(budgetTokens) токенов"
                ))
                continue
            }
            sections.append(section)
            if let citation = citation(for: ref, block: block) {
                citations.append(citation)
            }
            included.append(candidate.path)
        }

        // Never trim the request to fit the evidence budget: losing the user's
        // words is worse than exceeding it. If the request alone is bigger,
        // say so instead of cutting it.
        var text = render(sections: sections, unknowns: unknowns, dropped: dropped, detailedDrop: true)
        if text.utf8.count > budgetBytes {
            unknowns.append("запрос больше бюджета \(budgetTokens) токенов — отправлен целиком")
            text = render(sections: sections, unknowns: unknowns, dropped: dropped, detailedDrop: false)
        }

        return CompiledContextPack(
            sections: sections,
            citations: citations,
            unknowns: unknowns,
            manifest: ContextManifest(included: included, dropped: dropped, considered: candidates.count),
            estimatedTokens: (text.utf8.count + bytesPerToken - 1) / bytesPerToken,
            text: text,
            memoryIDs: memoryIDs
        )
    }

    // MARK: - Pieces

    /// One block per file: the most relevant symbol, or the line the user
    /// pointed at. Several overlapping blocks of the same file waste the
    /// budget and add nothing.
    private static func reference(for candidate: ContextCandidate,
                                  plan: ContextQueryPlan) -> TaskReference? {
        if plan.files.contains(candidate.path), let line = plan.lineNumbers.first {
            return TaskReference(path: candidate.path, symbol: nil,
                                 startLine: max(1, line - 5),
                                 endLine: line + 25, why: nil)
        }
        if let symbol = candidate.matchedSymbols.first {
            return TaskReference(path: candidate.path, symbol: symbol.name,
                                 startLine: nil, endLine: nil, why: nil)
        }
        return TaskReference(path: candidate.path, symbol: nil,
                             startLine: 1, endLine: nil, why: nil)
    }

    private static func citation(for reference: TaskReference, block: String) -> ContextCitation? {
        guard let header = block.split(separator: "\n").first else { return nil }
        // Header shape: `### path:start-end[ — symbol]`
        guard let colon = header.lastIndex(of: ":") else { return nil }
        let ranges = header[header.index(after: colon)...].split(separator: " ").first ?? ""
        let parts = ranges.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        return ContextCitation(path: reference.path, startLine: start, endLine: end, symbol: reference.symbol)
    }

    private static func render(sections: [ContextSection],
                               unknowns: [String],
                               dropped: [DroppedSource],
                               detailedDrop: Bool = true) -> String {
        var parts: [String] = []
        for section in sections {
            parts.append("## \(section.title)\n\(section.body)")
        }
        if !unknowns.isEmpty {
            parts.append("## Пробелы\n" + unknowns.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !dropped.isEmpty {
            if detailedDrop {
                parts.append("## Не вошло\n" + dropped.map { "- \($0.path) — \($0.reason)" }
                    .joined(separator: "\n"))
            } else {
                parts.append("## Не вошло\n- \(dropped.count) источников (полный список в манифесте)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
