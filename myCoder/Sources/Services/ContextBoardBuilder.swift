import Foundation

/// One file of the context board — a compact, structured view of a project
/// file. The LOCAL model reads the board to name real functions, types and
/// variables; it never writes code (user directive D7).
struct ContextBoardEntry: Equatable, Identifiable {
    let path: String
    let language: String
    let size: Int
    let symbols: [SymbolDeclaration]
    let imports: [String]
    /// First documentation line of the file, when there is one.
    let doc: String?
    /// Stable id — the relative path.
    var id: String { path }
}

/// The whole project as a structured map: paths, symbols, imports, docs.
/// Built locally and for free from the file index.
struct ContextBoard: Equatable {
    let projectPath: String
    let entries: [ContextBoardEntry]
    let builtAt: Date

    var fileCount: Int { entries.count }
}

/// Builds the context board from the file index.
enum ContextBoardBuilder {

    static func build(projectPath: String,
                      records: [FileIndexRecord],
                      maxSymbolsPerFile: Int = 60,
                      maxImportsPerFile: Int = 20,
                      now: Date = Date()) -> ContextBoard {
        let entries: [ContextBoardEntry] = records.compactMap { record in
            guard !ProjectFileIndexLogic.isSecretFile(relativePath: record.path) else { return nil }
            guard record.language.caseInsensitiveCompare("binary") != .orderedSame else { return nil }
            guard let text = record.searchableText, !text.isEmpty else { return nil }
            let symbols = Array(
                SymbolNameExtractor.declarations(in: text, language: record.language)
                    .prefix(max(0, maxSymbolsPerFile))
            )
            let imports = Array(
                imports(in: text, language: record.language)
                    .prefix(max(0, maxImportsPerFile))
            )
            return ContextBoardEntry(
                path: record.path,
                language: record.language,
                size: record.size,
                symbols: symbols,
                imports: imports,
                doc: documentation(in: text, language: record.language)
            )
        }
        return ContextBoard(projectPath: projectPath, entries: entries, builtAt: now)
    }

    /// The text the local model reads. One compact block per file.
    static func render(_ board: ContextBoard) -> String {
        guard !board.entries.isEmpty else { return "" }
        var lines: [String] = []
        for entry in board.entries {
            var header = "### \(entry.path) (\(entry.language), \(entry.size) bytes)"
            if let doc = entry.doc, !doc.isEmpty {
                header += "\n# \(doc)"
            }
            lines.append(header)
            if !entry.imports.isEmpty {
                lines.append("imports: " + entry.imports.joined(separator: ", "))
            }
            if !entry.symbols.isEmpty {
                let rendered = entry.symbols.map { "\($0.name)(\($0.kind))" }.joined(separator: ", ")
                lines.append("symbols: " + rendered)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Imports

    static func imports(in text: String, language: String) -> [String] {
        var result: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let module = importModule(line, language: language) {
                if !result.contains(module) { result.append(module) }
            }
        }
        return result
    }

    private static func importModule(_ line: String, language: String) -> String? {
        switch language {
        case "swift":
            if line.hasPrefix("import ") || line.hasPrefix("@testable import ") {
                let module = line
                    .replacingOccurrences(of: "@testable import ", with: "")
                    .replacingOccurrences(of: "import ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return module.isEmpty ? nil : module
            }
            return nil
        case "python":
            if line.hasPrefix("import ") {
                return String(line.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("from ") {
                guard let space = line.firstIndex(of: " ") else { return nil }
                return String(line[line.startIndex..<space])
            }
            return nil
        case "javascript", "typescript":
            if line.hasPrefix("import ") {
                guard let from = line.range(of: " from ") else { return nil }
                let tail = line[from.upperBound...].trimmingCharacters(in: .whitespaces)
                return tail.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            return nil
        case "go":
            if line.hasPrefix("import ") {
                let tail = String(line.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
                return tail.trimmingCharacters(in: CharacterSet(charactersIn: "\"`"))
            }
            return nil
        case "rust":
            if line.hasPrefix("use ") {
                let tail = String(line.dropFirst("use ".count)).trimmingCharacters(in: .whitespaces)
                return tail.split(separator: " ").first.map(String.init)
            }
            return nil
        case "java":
            if line.hasPrefix("import ") {
                let tail = String(line.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
                return tail.trimmingCharacters(in: CharacterSet(charactersIn: ";"))
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Documentation

    static func documentation(in text: String, language: String) -> String? {
        switch language {
        case "swift":
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                if line.hasPrefix("///") {
                    let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                } else if line.hasPrefix("//") || line.hasPrefix("import ") {
                    continue
                } else {
                    return nil
                }
            }
            return nil
        case "python":
            guard let start = text.range(of: "\"\"\""),
                  let end = text.range(of: "\"\"\"", range: start.upperBound..<text.endIndex) else {
                return nil
            }
            let body = text[start.upperBound..<end.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body.split(separator: "\n").first.map(String.init)
        case "javascript", "typescript", "java", "c", "cpp":
            guard let start = text.range(of: "/**") else { return nil }
            let tail = text[start.upperBound...]
            let firstLine = tail.split(separator: "\n").first.map(String.init) ?? ""
            let cleaned = firstLine
                .replacingOccurrences(of: "*/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " *"))
            return cleaned.isEmpty ? nil : cleaned
        default:
            return nil
        }
    }
}
