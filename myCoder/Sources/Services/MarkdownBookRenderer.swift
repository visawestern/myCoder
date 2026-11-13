import Foundation

/// Minimal, safe Markdown → HTML renderer for the standalone chat book.
///
/// Supports the constructs chat answers actually use: fenced code, headings,
/// paragraphs, lists, blockquotes, horizontal rules, inline code, bold,
/// italic and http(s) links. Everything is HTML-escaped first, so a message
/// can never inject markup into the exported file.
enum MarkdownBookRenderer {

    /// Input: Markdown text. Output: escaped HTML fragments.
    /// Dependencies: Foundation regular expressions only.
    static func render(_ markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var inCode = false
        var codeLanguage = ""
        var codeLines: [String] = []
        var listTag: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>")
            paragraph.removeAll()
        }

        func closeList() {
            if let tag = listTag {
                html.append("</\(tag)>")
                listTag = nil
            }
        }

        func flushCode() {
            guard inCode else { return }
            let language = codeLanguage.isEmpty
                ? ""
                : " class=\"language-\(escape(codeLanguage))\""
            html.append("<pre><code\(language)>"
                + escape(codeLines.joined(separator: "\n"))
                + "</code></pre>")
            codeLines.removeAll()
            codeLanguage = ""
            inCode = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                } else {
                    flushParagraph()
                    closeList()
                    inCode = true
                    codeLanguage = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                closeList()
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                closeList()
                html.append("<hr>")
                continue
            }
            if let heading = heading(trimmed) {
                flushParagraph()
                closeList()
                html.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                closeList()
                html.append("<blockquote>\(inline(String(trimmed.dropFirst(2))))</blockquote>")
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                if listTag != "ul" {
                    closeList()
                    html.append("<ul>")
                    listTag = "ul"
                }
                html.append("<li>\(inline(String(trimmed.dropFirst(2))))</li>")
                continue
            }
            if let item = orderedItem(trimmed) {
                flushParagraph()
                if listTag != "ol" {
                    closeList()
                    html.append("<ol>")
                    listTag = "ol"
                }
                html.append("<li>\(inline(item))</li>")
                continue
            }
            paragraph.append(trimmed)
        }
        if inCode { flushCode() }
        flushParagraph()
        closeList()
        return html.joined(separator: "\n")
    }

    /// HTML-escape text for any element or attribute.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Block helpers

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return (level, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let match = firstMatch(pattern: #"^\d+\.\s+(.+)$"#, in: line) else { return nil }
        return match[1]
    }

    // MARK: - Inline helpers

    private static func inline(_ raw: String) -> String {
        var text = escape(raw)
        var codeTokens: [String] = []
        text = replacing(pattern: "`([^`]+)`", in: text) { groups in
            codeTokens.append("<code>\(groups[1])</code>")
            return "\u{E000}\(codeTokens.count - 1)\u{E001}"
        }
        text = replacing(pattern: #"\*\*([^*]+)\*\*"#, in: text) { groups in
            "<strong>\(groups[1])</strong>"
        }
        text = replacing(pattern: #"\*([^*]+)\*"#, in: text) { groups in
            "<em>\(groups[1])</em>"
        }
        text = replacing(
            pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#,
            in: text
        ) { groups in
            "<a href=\"\(groups[2])\" target=\"_blank\" rel=\"noopener noreferrer\">\(groups[1])</a>"
        }
        for (index, token) in codeTokens.enumerated() {
            text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: token)
        }
        return text
    }

    private static func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return groups
    }

    private static func replacing(pattern: String, in text: String,
                                  transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor,
                                                    length: match.range.location - cursor))
            }
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }
}
