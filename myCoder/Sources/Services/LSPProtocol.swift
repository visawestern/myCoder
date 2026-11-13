import Foundation

// MARK: - Wire types

/// One zero-based LSP position (line + UTF-16 character offset).
struct LSPPosition: Codable, Equatable, Sendable {
    var line: Int
    var character: Int
}

struct LSPRange: Codable, Equatable, Sendable {
    var start: LSPPosition
    var end: LSPPosition
}

struct LSPLocation: Codable, Equatable, Sendable {
    var uri: String
    var range: LSPRange
}

/// The subset of `textDocument/publishDiagnostics` the agent needs.
struct LSPDiagnostic: Codable, Equatable, Sendable {
    var range: LSPRange
    var severity: Int?
    var message: String
    var source: String?
}

// MARK: - JSON-RPC framing

/// Encodes and decodes the LSP base protocol: `Content-Length: N\r\n\r\n`.
/// Pure functions only, so framing bugs are testable without a server.
enum LSPMessageCodec {
    struct Decoded: Equatable {
        var messages: [Data]
        var remaining: Data
    }

    /// Wraps one JSON payload into an LSP frame.
    /// Input: JSON bytes. Output: header + body. No dependencies.
    static func frame(json: Data) -> Data {
        var data = Data("Content-Length: \(json.count)\r\n\r\n".utf8)
        data.append(json)
        return data
    }

    /// Extracts every complete frame from a stream buffer and returns the
    /// unfinished tail. Input: accumulated bytes. Output: messages + remainder.
    /// Dependencies: Foundation only.
    static func decode(buffer: Data) -> Decoded {
        // Rebase once so every offset below is a plain distance from byte 0.
        // `Data` slices keep the PARENT's indices (and `removeFirst` leaves
        // `startIndex` advanced), so mixing `range(of:)` results with `prefix`
        // read the second header from the wrong base — the original bug where
        // only the first frame of a two-frame buffer was decoded.
        let input = Data(buffer)
        var messages: [Data] = []
        var cursor = 0
        while cursor < input.count {
            guard let headerEnd = headerTerminator(in: input, from: cursor) else { break }
            let headerData = input.subdata(in: cursor..<headerEnd.offset)
            guard let length = contentLength(in: headerData), length >= 0 else {
                // A malformed header can never become a frame: skip it so the
                // stream cannot spin forever on the same bytes.
                cursor = headerEnd.endOffset
                continue
            }
            guard input.count >= headerEnd.endOffset + length else { break }
            messages.append(input.subdata(in: headerEnd.endOffset..<(headerEnd.endOffset + length)))
            cursor = headerEnd.endOffset + length
        }
        let remaining = cursor < input.count
            ? input.subdata(in: cursor..<input.count)
            : Data()
        return Decoded(messages: messages, remaining: remaining)
    }

    private struct HeaderEnd {
        let offset: Int
        let endOffset: Int
    }

    private static func headerTerminator(in data: Data, from offset: Int) -> HeaderEnd? {
        let searchRange = offset..<data.count
        if let range = data.range(of: Data("\r\n\r\n".utf8), in: searchRange) {
            return HeaderEnd(offset: range.lowerBound, endOffset: range.upperBound)
        }
        if let range = data.range(of: Data("\n\n".utf8), in: searchRange) {
            return HeaderEnd(offset: range.lowerBound, endOffset: range.upperBound)
        }
        return nil
    }

    private static func contentLength(in header: Data) -> Int? {
        guard let text = String(data: header, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            return Int(parts[1])
        }
        return nil
    }
}

// MARK: - Language mapping

struct LSPLanguage: Equatable, Sendable {
    let id: String
    let displayName: String
}

/// Maps a file extension to the LSP language id and to the display name used
/// in `~/.mycoder/lsp.json` (`languages: ["Swift", ...]`).
enum LSPLanguageMap {
    private static let byExtension: [String: LSPLanguage] = [
        "swift": LSPLanguage(id: "swift", displayName: "Swift"),
        "ts": LSPLanguage(id: "typescript", displayName: "TypeScript"),
        "tsx": LSPLanguage(id: "typescriptreact", displayName: "TypeScript"),
        "mts": LSPLanguage(id: "typescript", displayName: "TypeScript"),
        "cts": LSPLanguage(id: "typescript", displayName: "TypeScript"),
        "js": LSPLanguage(id: "javascript", displayName: "JavaScript"),
        "jsx": LSPLanguage(id: "javascriptreact", displayName: "JavaScript"),
        "mjs": LSPLanguage(id: "javascript", displayName: "JavaScript"),
        "cjs": LSPLanguage(id: "javascript", displayName: "JavaScript"),
        "py": LSPLanguage(id: "python", displayName: "Python"),
        "pyi": LSPLanguage(id: "python", displayName: "Python"),
        "rs": LSPLanguage(id: "rust", displayName: "Rust"),
        "go": LSPLanguage(id: "go", displayName: "Go"),
        "c": LSPLanguage(id: "c", displayName: "C"),
        "h": LSPLanguage(id: "c", displayName: "C"),
        "cc": LSPLanguage(id: "cpp", displayName: "C++"),
        "cpp": LSPLanguage(id: "cpp", displayName: "C++"),
        "cxx": LSPLanguage(id: "cpp", displayName: "C++"),
        "hpp": LSPLanguage(id: "cpp", displayName: "C++"),
        "hh": LSPLanguage(id: "cpp", displayName: "C++"),
        "hxx": LSPLanguage(id: "cpp", displayName: "C++"),
        "m": LSPLanguage(id: "objective-c", displayName: "Objective-C"),
        "mm": LSPLanguage(id: "objective-cpp", displayName: "Objective-C"),
        "java": LSPLanguage(id: "java", displayName: "Java"),
        "html": LSPLanguage(id: "html", displayName: "HTML"),
        "htm": LSPLanguage(id: "html", displayName: "HTML"),
        "css": LSPLanguage(id: "css", displayName: "CSS"),
        "scss": LSPLanguage(id: "scss", displayName: "SCSS"),
        "less": LSPLanguage(id: "less", displayName: "Less"),
        "json": LSPLanguage(id: "json", displayName: "JSON"),
        "jsonc": LSPLanguage(id: "jsonc", displayName: "JSON"),
        "zig": LSPLanguage(id: "zig", displayName: "Zig")
    ]

    /// Input: a file path. Output: its language, or nil when LSP cannot help.
    static func language(forPath path: String) -> LSPLanguage? {
        let ext = (path as NSString).pathExtension.lowercased()
        return byExtension[ext]
    }

    /// Whether a configured server's `languages` list covers this language.
    /// Comparison is case-insensitive because configs are user-editable.
    static func serverSupports(languages: [String], language: LSPLanguage) -> Bool {
        languages.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(language.displayName) == .orderedSame
        }
    }
}

// MARK: - Positions and URIs

enum LSPPositionLogic {
    /// Converts a 1-based user line/column to the zero-based UTF-16 position
    /// LSP expects. Input: line, column, full text. Output: clamped position.
    /// Dependencies: Foundation string indexing.
    static func position(line: Int, column: Int, in text: String) -> LSPPosition {
        let lines = text.components(separatedBy: "\n")
        let lineIndex = max(0, min(line - 1, max(0, lines.count - 1)))
        let lineText = lines.isEmpty ? "" : lines[lineIndex]
        let columnIndex = max(0, column - 1)
        let prefix = lineText.prefix(min(columnIndex, lineText.count))
        return LSPPosition(line: lineIndex, character: prefix.utf16.count)
    }

    /// Converts a zero-based LSP position back to the 1-based line/column the
    /// agent sees. Input: position + text. Output: line, column.
    static func userPosition(_ position: LSPPosition, in text: String) -> (line: Int, column: Int) {
        let lines = text.components(separatedBy: "\n")
        let lineIndex = max(0, min(position.line, max(0, lines.count - 1)))
        let lineText = lines.isEmpty ? "" : lines[lineIndex]
        let clamped = max(0, min(position.character, lineText.utf16.count))
        let prefix = String(decoding: lineText.utf16.prefix(clamped), as: UTF16.self)
        return (lineIndex + 1, prefix.count + 1)
    }
}

enum LSPDocumentURI {
    /// Input: filesystem path. Output: percent-encoded `file://` URI.
    static func make(path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    /// Input: `file://` URI. Output: filesystem path (percent-decoded).
    static func path(fromURI uri: String) -> String {
        URL(string: uri)?.path ?? uri
    }
}

// MARK: - Diagnostics report

enum LSPDiagnosticsFormatter {
    /// Formats diagnostics as a compact, model-readable report.
    /// Input: display path, diagnostics, cap. Output: text with counts and
    /// one-based positions. Dependencies: none.
    static func summary(path: String,
                        diagnostics: [LSPDiagnostic],
                        maxItems: Int = 20) -> String {
        guard !diagnostics.isEmpty else {
            return "LSP diagnostics for \(path): no errors or warnings."
        }
        let errors = diagnostics.filter { $0.severity == 1 }.count
        let warnings = diagnostics.filter { $0.severity == 2 }.count
        let counts = [errors > 0 ? "\(errors) error\(errors == 1 ? "" : "s")" : nil,
                      warnings > 0 ? "\(warnings) warning\(warnings == 1 ? "" : "s")" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
        var lines = ["LSP diagnostics for \(path): \(counts.isEmpty ? "\(diagnostics.count) issue(s)" : counts)"]
        for diagnostic in diagnostics.prefix(max(0, maxItems)) {
            let line = diagnostic.range.start.line + 1
            let column = diagnostic.range.start.character + 1
            let severity = label(for: diagnostic.severity)
            let source = diagnostic.source.map { " [\($0)]" } ?? ""
            lines.append("- \(severity) \(line):\(column): \(diagnostic.message)\(source)")
        }
        if diagnostics.count > maxItems {
            lines.append("- and \(diagnostics.count - maxItems) more")
        }
        return lines.joined(separator: "\n")
    }

    private static func label(for severity: Int?) -> String {
        switch severity {
        case 1: return "error"
        case 2: return "warning"
        case 3: return "info"
        case 4: return "hint"
        default: return "issue"
        }
    }
}
