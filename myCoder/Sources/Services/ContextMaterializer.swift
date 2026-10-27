import Foundation

/// Turns an atomic task into the real code it points at.
///
/// The local model only named files and symbols; the host reads those files
/// from disk and builds one focused context block. Nothing is invented here —
/// every line in the output comes from a real file of the project.
enum ContextMaterializer {

    static func materialize(task: AtomicTask, projectRoot: String) throws -> String {
        var sections: [String] = []

        sections.append("## Атомарная задача\n\(task.atomicTask)")

        if !task.tddSteps.isEmpty {
            let steps = task.tddSteps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            sections.append("## TDD-порядок\n\(steps)")
        }

        if !task.acceptance.isEmpty {
            let criteria = task.acceptance.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Критерии приёмки\n\(criteria)")
        }

        var codeBlocks: [String] = []
        for reference in task.refs {
            codeBlocks.append(try codeBlock(for: reference, projectRoot: projectRoot))
        }
        if !codeBlocks.isEmpty {
            sections.append("## Код\n" + codeBlocks.joined(separator: "\n"))
        }

        if !task.knownGaps.isEmpty {
            let gaps = task.knownGaps.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Чего не знаем\n\(gaps)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Code blocks

    private static func codeBlock(for reference: TaskReference, projectRoot: String) throws -> String {
        let path = reference.path
        let url = resolve(path: path, projectRoot: projectRoot)
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LocalCompilerError.materializationFailed(
                path: path,
                reason: error.localizedDescription
            )
        }

        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else {
            throw LocalCompilerError.materializationFailed(path: path, reason: "empty file")
        }

        let language = ProjectFileIndexLogic.language(forExtension: url.pathExtension)
        var range: ClosedRange<Int>
        var note: String?

        if let start = reference.startLine {
            let first = max(1, start)
            // A reference beyond the file is a hard error: silently clamping
            // would hand the model code it did not ask for.
            guard first <= lines.count else {
                throw LocalCompilerError.materializationFailed(
                    path: path,
                    reason: "startLine \(first) is beyond the end of the file (\(lines.count) lines)"
                )
            }
            if let end = reference.endLine, end < first {
                throw LocalCompilerError.materializationFailed(
                    path: path,
                    reason: "endLine \(end) is before startLine \(first)"
                )
            }
            let requestedLast = reference.endLine ?? (first + 79)
            let last = min(lines.count, max(first, requestedLast))
            range = first...last
            if let end = reference.endLine, end > lines.count {
                note = "файл заканчивается на строке \(lines.count)"
            }
        } else if let symbol = reference.symbol, !symbol.isEmpty {
            let cleaned = symbol.replacingOccurrences(of: "()", with: "")
            let declarations = SymbolNameExtractor.declarations(in: text, language: language)
            if let match = declarations.first(where: { $0.name == cleaned }) {
                let first = max(1, match.line - 4)
                let last = min(lines.count, match.line + 59)
                range = first...max(first, last)
            } else {
                range = 1...min(lines.count, 60)
                note = "символ '\(symbol)' не найден, показан файл целиком (начало)"
            }
        } else {
            range = 1...lines.count
        }

        // `range` is a 1-based line range; `lines` is a 0-based array.
        let body = lines[(range.lowerBound - 1)...(range.upperBound - 1)].joined(separator: "\n")
        var header = "### \(path):\(range.lowerBound)-\(range.upperBound)"
        if let symbol = reference.symbol, !symbol.isEmpty {
            header += " — \(symbol)"
        }
        var block = header
        if let note {
            block += "\n(_\(note)_)"
        }
        if let why = reference.why, !why.isEmpty {
            block += "\n(зачем: \(why))"
        }
        block += "\n" + body
        return block
    }

    private static func resolve(path: String, projectRoot: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        let root = URL(fileURLWithPath: projectRoot, isDirectory: true)
        return root.appendingPathComponent(path)
    }
}
