import Foundation

enum ProjectFileSearchLogic {
    static func search(query: String,
                       records: [FileIndexRecord],
                       limit: Int = 100) -> [FileIndexRecord] {
        let terms = tokenize(query)
        guard !terms.isEmpty, limit > 0 else { return [] }

        let scored = records.compactMap { record -> (FileIndexRecord, Int)? in
            guard record.language.caseInsensitiveCompare("binary") != .orderedSame else { return nil }
            let path = record.path.lowercased()
            let content = record.searchableText?.lowercased() ?? ""
            let contentMatch = terms.allSatisfy { content.contains($0) }
            let pathMatch = terms.allSatisfy { path.contains($0) }
            guard contentMatch || pathMatch else { return nil }
            return (record, contentMatch ? 2 : 1)
        }

        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.path.localizedStandardCompare($1.0.path) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func tokenize(_ query: String) -> [String] {
        query
            .split { $0.isWhitespace || $0.isNewline }
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { !$0.isEmpty }
    }
}
