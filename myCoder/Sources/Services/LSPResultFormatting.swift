import Foundation

/// Turns raw LSP JSON results into compact text the model can read.
///
/// Every function is pure and accepts the `Any` produced by
/// `JSONSerialization`, so the exact shapes servers return (single location,
/// array of locations, LocationLink, `CompletionList`, MarkupContent or an
/// array of MarkedString) are all testable without a live server.
enum LSPResultFormatting {

    /// Format `textDocument/definition` and `textDocument/references` results.
    /// Input: raw result + a label ("definition"/"reference"). Output: one
    /// header plus `path:line:column` rows. Dependencies: LSPDocumentURI.
    static func locations(_ result: Any?, kind: String) -> String {
        let entries = locationEntries(result)
        guard !entries.isEmpty else { return "no \(kind)s found" }
        var lines = ["\(entries.count) \(kind)\(entries.count == 1 ? "" : "s"):"]
        for entry in entries.prefix(50) {
            let path = LSPDocumentURI.path(fromURI: entry.uri)
            lines.append("- \(path):\(entry.line):\(entry.column)")
        }
        if entries.count > 50 {
            lines.append("- and \(entries.count - 50) more")
        }
        return lines.joined(separator: "\n")
    }

    /// Format `textDocument/hover` contents (string, MarkupContent,
    /// MarkedString or an array of them). Input: raw result. Output: text or
    /// an explicit "no hover information". Dependencies: none.
    static func hover(_ result: Any?) -> String {
        guard let object = result as? [String: Any],
              let contents = object["contents"] else { return "no hover information" }
        let text = hoverText(contents).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "no hover information" }
        return String(text.prefix(4000))
    }

    /// Format `textDocument/completion` items. Input: raw result + cap.
    /// Output: count header plus `label — detail (Kind)` rows.
    /// Dependencies: none.
    static func completions(_ result: Any?, maxItems: Int) -> String {
        let items: [[String: Any]]
        if let array = result as? [[String: Any]] {
            items = array
        } else if let object = result as? [String: Any],
                  let array = object["items"] as? [[String: Any]] {
            items = array
        } else {
            items = []
        }
        guard !items.isEmpty else { return "no completion items" }
        var lines = ["\(items.count) completion item\(items.count == 1 ? "" : "s"):"]
        for item in items.prefix(max(0, maxItems)) {
            let label = item["label"] as? String ?? "?"
            var row = "- \(label)"
            if let detail = item["detail"] as? String, !detail.isEmpty {
                row += " — \(detail)"
            }
            if let kind = item["kind"] as? Int {
                row += " (\(kindName(kind)))"
            }
            lines.append(row)
        }
        if items.count > maxItems {
            lines.append("- and \(items.count - maxItems) more")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private struct LocationEntry {
        let uri: String
        let line: Int
        let column: Int
    }

    private static func locationEntries(_ result: Any?) -> [LocationEntry] {
        if let array = result as? [[String: Any]] {
            return array.compactMap(locationEntry)
        }
        if let single = result as? [String: Any] {
            return locationEntry(single).map { [$0] } ?? []
        }
        return []
    }

    private static func locationEntry(_ object: [String: Any]) -> LocationEntry? {
        // LocationLink uses targetUri/targetSelectionRange; plain Location
        // uses uri/range.
        let uri = object["uri"] as? String ?? object["targetUri"] as? String
        let range = object["range"] as? [String: Any]
            ?? object["targetSelectionRange"] as? [String: Any]
            ?? object["targetRange"] as? [String: Any]
        guard let uri,
              let start = range?["start"] as? [String: Any],
              let line = start["line"] as? Int,
              let character = start["character"] as? Int else { return nil }
        return LocationEntry(uri: uri, line: line + 1, column: character + 1)
    }

    private static func hoverText(_ contents: Any) -> String {
        if let text = contents as? String { return text }
        if let object = contents as? [String: Any] {
            if let value = object["value"] as? String { return value }
            return ""
        }
        if let array = contents as? [Any] {
            return array.map(hoverText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return ""
    }

    private static func kindName(_ kind: Int) -> String {
        switch kind {
        case 1: return "Text"
        case 2: return "Method"
        case 3: return "Function"
        case 4: return "Constructor"
        case 5: return "Field"
        case 6: return "Variable"
        case 7: return "Class"
        case 8: return "Interface"
        case 9: return "Module"
        case 10: return "Property"
        case 11: return "Unit"
        case 12: return "Value"
        case 13: return "Enum"
        case 14: return "Keyword"
        case 15: return "Snippet"
        case 16: return "Color"
        case 17: return "File"
        case 18: return "Reference"
        case 19: return "Folder"
        case 20: return "EnumMember"
        case 21: return "Constant"
        case 22: return "Struct"
        case 23: return "Event"
        case 24: return "Operator"
        case 25: return "TypeParameter"
        default: return "Item"
        }
    }
}

/// Chooses which installed language server should handle a file.
/// Pure so registry/config edge cases are unit-testable.
enum LSPServerSelection {
    /// Input: installed records + file path. Output: the first enabled server
    /// whose `languages` cover the file's language, ordered by id for a stable
    /// choice. Dependencies: LSPLanguageMap.
    static func select(records: [InstalledLSPRecord], path: String) -> InstalledLSPRecord? {
        guard let language = LSPLanguageMap.language(forPath: path) else { return nil }
        return records
            .filter(\.isEnabled)
            .filter { LSPLanguageMap.serverSupports(languages: $0.languages, language: language) }
            .sorted { $0.id < $1.id }
            .first
    }
}
