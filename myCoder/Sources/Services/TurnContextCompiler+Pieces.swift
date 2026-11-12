import Foundation

extension TurnContextCompiler {

    /// Когда точная ссылка не сработала (устаревший символ/строка,
    /// нестандартная кодировка), не теряем файл: читаем его целиком с
    /// пометкой причины (запрос 2026-11-13).
    static func fallbackBlock(path: String,
                              projectRoot: String,
                              reason: String) -> String? {
        try? ContextMaterializer.block(
            for: TaskReference(path: path, symbol: nil,
                               startLine: nil, endLine: nil, why: nil),
            projectRoot: projectRoot,
            fallbackReason: reason
        )
    }

    /// One block per file: the most relevant symbol, or the line the user
    /// pointed at. Several overlapping blocks of the same file waste the
    /// budget and add nothing.
    static func reference(for candidate: ContextCandidate,
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

    static func citation(for reference: TaskReference, block: String) -> ContextCitation? {
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
}
