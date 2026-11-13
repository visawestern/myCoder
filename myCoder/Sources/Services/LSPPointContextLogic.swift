import Foundation

/// LSP-assisted point context (plan item 10).
///
/// When a language server covers the files that will enter the point-context
/// pack, its diagnostics are included as a separate, clearly-sourced section —
/// errors/warnings the model can act on without re-reading the code. The rule:
///   • a fact is ONLY a non-nil report from the real language server;
///   • unavailable server ⇒ no facts ⇒ no section (honest skip, never
///     fabricated data);
///   • the section is separate from the code blocks, so LSP data never
///     duplicates already-read code.
///
/// Input: candidate file paths + an injectable diagnostics provider.
/// Output: `LSPPointFact`s and a `ContextSection` with a visible source
/// marker.
/// Dependencies: `LSPManager.diagnosticsSummary` (default provider),
/// `ContextSection`.
enum LSPPointContextLogic {

    /// One language-server fact: path + formatted diagnostics text.
    struct LSPPointFact: Equatable {
        let path: String
        let text: String
    }

    /// How many files receive an LSP diagnostics probe per pack.
    static let maxProbedFiles = 5

    /// Collect facts for candidate files (bounded count).
    ///
    /// Input: candidate paths in rank order, project root, diagnostics
    /// provider (injectable for tests; production uses `LSPManager`).
    /// Output: facts in path order; a file whose server is unavailable or has
    /// nothing to report is skipped silently.
    /// Dependencies: `diagnostics` closure.
    static func facts(
        candidates: [String],
        projectRoot: String,
        limit: Int = maxProbedFiles,
        diagnostics: (String, String) async -> String? = { path, root in
            await LSPManager.shared.diagnosticsSummary(path: path, projectRoot: root)
        }
    ) async -> [LSPPointFact] {
        let paths = Array(candidates.prefix(max(0, limit)))
        var result: [LSPPointFact] = []
        for path in paths {
            guard let text = await diagnostics(path, projectRoot), !text.isEmpty else {
                continue
            }
            result.append(LSPPointFact(path: path, text: text))
        }
        return result
    }

    /// Build the LSP section for the pack.
    ///
    /// Input: facts.
    /// Output: a section titled with the source marker («источник: языковой
    /// сервер») or nil when there are no facts (server unavailable or nothing
    /// to report — the pack continues honestly without it).
    /// Dependencies: `ContextSection`.
    static func section(facts: [LSPPointFact]) -> ContextSection? {
        guard !facts.isEmpty else { return nil }
        let body = facts.map { fact -> String in
            "### \(fact.path)\n\(fact.text)"
        }.joined(separator: "\n\n")
        return ContextSection(
            title: "Диагностика LSP (источник: языковой сервер)",
            body: body
        )
    }

    /// Whether a probe is worth attempting for these paths (non-empty paths).
    static func shouldProbe(candidates: [String]) -> Bool {
        !candidates.isEmpty
    }

    /// Select candidate paths for the LSP probe from the project index.
    ///
    /// Input: index records, the query terms, an upper bound.
    /// Output: up to `limit` paths, files matching explicit query tokens first,
    /// then records whose language is server-capable, then plain first-N.
    /// Dependencies: none (pure selection over records).
    static func candidatePaths(records: [FileIndexRecord],
                               query: String,
                               limit: Int = maxProbedFiles) -> [String] {
        let terms = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        func score(_ record: FileIndexRecord) -> Int {
            let path = record.path.lowercased()
            return terms.reduce(0) { $0 + (path.contains($1) ? 1 : 0) }
        }
        let ranked = records
            .map { (record: $0, score: score($0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.record.path)
        if !ranked.isEmpty { return ranked }
        return records.prefix(limit).map(\.path)
    }
}
