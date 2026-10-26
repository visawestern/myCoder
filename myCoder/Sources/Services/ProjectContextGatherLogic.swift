import Foundation

/// Host-side project auto-search for roadmap item A/B: before the model is
/// called, the host gathers the project files matching the user's request and
/// prepends them as a `<project-context>` block to the MODEL-BOUND text.
/// Ranking reuses `ProjectFileSearchLogic`; this enum only caps the budget and
/// formats the block. Displayed chat bubbles keep the raw user text.
enum ProjectContextGatherLogic {
    struct ContextBundle: Equatable {
        let paths: [String]
        let snippet: String
        var isEmpty: Bool { paths.isEmpty }
    }

    static let defaultMaxFiles = 5
    static let defaultMaxChars = 4000
    static let maxExcerptLinesPerFile = 2
    static let maxExcerptLineLength = 160

    /// Gather matching files. Empty/whitespace queries and empty records
    /// yield an empty bundle without touching the model payload.
    static func gather(
        query: String,
        records: [FileIndexRecord],
        maxFiles: Int = defaultMaxFiles,
        maxChars: Int = defaultMaxChars
    ) -> ContextBundle {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxFiles > 0, maxChars > 0 else {
            return ContextBundle(paths: [], snippet: "")
        }
        let matches = ProjectFileSearchLogic.search(query: trimmed, records: records, limit: maxFiles)
        guard !matches.isEmpty else { return ContextBundle(paths: [], snippet: "") }
        let terms = tokenizedTerms(trimmed)
        var sections: [String] = []
        var used = 0
        for record in matches {
            let excerpts = excerptLines(in: record.searchableText, terms: terms)
            var section = "### \(record.path)"
            for line in excerpts {
                let addition = "\n" + line
                guard used + section.count + addition.count <= maxChars else { break }
                section += addition
            }
            guard used + section.count <= maxChars else { break }
            used += section.count + 1
            sections.append(section)
        }
        guard !sections.isEmpty else { return ContextBundle(paths: [], snippet: "") }
        return ContextBundle(paths: sections.indices.map { matches[$0].path }, snippet: sections.joined(separator: "\n"))
    }

    /// Ready-to-prepend block, or `""` when there is nothing to add.
    static func block(
        query: String,
        records: [FileIndexRecord],
        maxFiles: Int = defaultMaxFiles,
        maxChars: Int = defaultMaxChars
    ) -> String {
        let bundle = gather(query: query, records: records, maxFiles: maxFiles, maxChars: maxChars)
        guard !bundle.isEmpty else { return "" }
        return "<project-context>\n\(bundle.snippet)\n</project-context>"
    }

    // MARK: - Private

    private static func tokenizedTerms(_ query: String) -> [String] {
        query.split { $0.isWhitespace || $0.isNewline }
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func excerptLines(in text: String?, terms: [String]) -> [String] {
        guard let text, !terms.isEmpty else { return [] }
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard terms.contains(where: { lower.contains($0) }) else { continue }
            result.append(String(line.prefix(maxExcerptLineLength)))
            if result.count >= maxExcerptLinesPerFile { break }
        }
        return result
    }
}
