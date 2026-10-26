import Foundation

/// One markdown block of a document.
enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case codeBlock(String, String)
    case inlineCode(String)
    case bold(String)
    case bulletItem(String)
    case numberedItem(Int, String)
    case checkbox(Bool, String)
    case blockquote(String)
    case horizontalRule
    case table([[String]])
    /// Display math: `$$ … $$` or `\[…\]` — rendered via `LaTeXMathRenderer`.
    case math(String)
    case paragraph(String)
}

/// Splits a markdown document into blocks.
///
/// The parser is pure and shared: the rich SwiftUI renderer and the single
/// surface selectable renderer must agree on the document structure, otherwise
/// the same text would look different depending on how it is drawn.
enum MarkdownDocumentParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.codeBlock(lang, code.joined(separator: "\n")))
            } else if let math = mathBlock(lines, at: &i) {
                blocks.append(.math(math))
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(1, String(line.dropFirst(2))))
                i += 1
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(2, String(line.dropFirst(3))))
                i += 1
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(3, String(line.dropFirst(4))))
                i += 1
            } else if line.hasPrefix("- [") {
                let rest = String(line.dropFirst(2).dropFirst())
                let checked = rest.hasPrefix("x") || rest.hasPrefix("X")
                let content = String(rest.dropFirst().dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.checkbox(checked, content))
                i += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bulletItem(String(line.dropFirst(2))))
                i += 1
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let numStr = String(line[..<match.upperBound]).trimmingCharacters(in: .whitespaces)
                let num = Int(numStr.replacingOccurrences(of: ".", with: "")) ?? 0
                let content = String(line[match.upperBound...])
                blocks.append(.numberedItem(num, content))
                i += 1
            } else if line.hasPrefix("> ") {
                blocks.append(.blockquote(String(line.dropFirst(2))))
                i += 1
            } else if line.trimmingCharacters(in: .whitespaces) == "---" || line.trimmingCharacters(in: .whitespaces) == "***" {
                blocks.append(.horizontalRule)
                i += 1
            } else if isTableStart(lines, at: i) {
                blocks.append(.table(parseTable(lines, at: &i)))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
            } else {
                var paragraph = line
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !lines[i].hasPrefix("#") && !lines[i].hasPrefix("```") && !lines[i].hasPrefix("- ") && !lines[i].hasPrefix("* ") && !lines[i].hasPrefix("> ") && !isMathBlockStart(lines[i]) {
                    paragraph += " " + lines[i]
                    i += 1
                }
                blocks.append(.paragraph(paragraph))
            }
        }

        return blocks
    }

    private static func isTableStart(_ lines: [String], at i: Int) -> Bool {
        guard i + 1 < lines.count,
              splitTableRow(lines[i]).count > 1 else { return false }
        return isTableSeparatorRow(lines[i + 1])
    }

    private static func parseTable(_ lines: [String], at i: inout Int) -> [[String]] {
        var rows: [[String]] = []
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let cells = splitTableRow(lines[i])
            if !isTableSeparatorRow(lines[i]) {
                rows.append(cells)
            }
            i += 1
        }
        return rows
    }

    private static func splitTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var parts = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let core = cell.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }
}

/// One inline fragment of a markdown text run.
enum MarkdownInlineToken: Equatable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(String, String)
    /// Inline-LaTeX run (`\(…)`, `\[…]`, mathy `$…$`), pre-rendered.
    case mathInline(String)
}

/// Splits a text run into inline fragments (bold, italic, code, links).
enum MarkdownInlineParser {
    private enum Token {
        case bold, italic, code, link, parenMath, bracketMath, dollarMath

        var pattern: String {
            switch self {
            case .bold: return #"\*\*(.+?)\*\*"#
            case .italic: return #"(?<!\*)\*([^*\n]+?)\*(?!\*)|(?<!_)_([^_\n]+?)_(?!_)"#
            case .code: return #"`(.+?)`"#
            case .link: return #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#
            case .parenMath: return #"\\\(([^\n)]+?)\)"#
            case .bracketMath: return #"\\\[([^\n\[\]]+?)\]"#
            case .dollarMath: return #"\$([^\$\n]+?)\$"#
            }
        }

        func parts(from matched: String) -> [MarkdownInlineToken] {
            switch self {
            case .bold:
                return [.bold(String(matched.dropFirst(2).dropLast(2)))]
            case .italic:
                return [.italic(String(matched.dropFirst().dropLast()))]
            case .code:
                return [.code(String(matched.dropFirst().dropLast()))]
            case .link:
                let groups = captureGroups(matched, pattern: #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#)
                if groups.count >= 2, !groups[0].isEmpty, !groups[1].isEmpty {
                    return [.link(groups[0], groups[1])]
                }
                return [.text(matched)]
            case .parenMath, .bracketMath:
                let inner = String(matched.dropFirst(2).dropLast(2))
                return [.mathInline(LaTeXMathRenderer.render(inner))]
            case .dollarMath:
                return Token.latexDollarPart(from: matched)
            }
        }

        private static func latexDollarPart(from matched: String) -> [MarkdownInlineToken] {
            let inner = String(matched.dropFirst().dropLast())
            guard LaTeXMathRenderer.looksLikeMath(inner) else {
                return [.text(matched)]
            }
            return [.mathInline(LaTeXMathRenderer.render(inner))]
        }
    }

    static func parse(_ s: String) -> [MarkdownInlineToken] {
        let processedText = resolveLaTeXSymbols(s)
        var parts: [MarkdownInlineToken] = []
        var remaining = processedText
        let bareURLPattern = #"https?://[^\s)\]]+"#

        while !remaining.isEmpty {
            // Pick the earliest match so parts come out in source order.
            var earliest: (token: Token, range: Range<String.Index>)?
            for token in [Token.code, .bold, .italic, .link, .parenMath, .bracketMath, .dollarMath] {
                guard let range = remaining.range(of: token.pattern, options: .regularExpression) else { continue }
                if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                    earliest = (token, range)
                }
            }

            // A bare http(s) URL not wrapped in [title](url).
            let bareRange = remaining.range(of: bareURLPattern, options: .regularExpression)

            guard let match = earliest else {
                if let r = bareRange, r.lowerBound >= remaining.startIndex {
                    if r.lowerBound > remaining.startIndex {
                        parts.append(.text(String(remaining[..<r.lowerBound])))
                    }
                    let url = String(remaining[r])
                    parts.append(.link(url, url))
                    remaining = String(remaining[r.upperBound...])
                    continue
                }
                parts.append(.text(remaining))
                break
            }

            // A bare URL starting before the earliest structured token wins,
            // so `visit https://x.com then **bold**` keeps source order.
            if let r = bareRange, r.lowerBound < match.range.lowerBound {
                if r.lowerBound > remaining.startIndex {
                    parts.append(.text(String(remaining[..<r.lowerBound])))
                }
                let url = String(remaining[r])
                parts.append(.link(url, url))
                remaining = String(remaining[r.upperBound...])
                continue
            }

            if match.range.lowerBound > remaining.startIndex {
                parts.append(.text(String(remaining[..<match.range.lowerBound])))
            }
            parts.append(contentsOf: match.token.parts(from: String(remaining[match.range])))
            remaining = String(remaining[match.range.upperBound...])
        }

        return mergeAdjacentText(parts)
    }

    /// Rejected math candidates (literal dollar amounts) leave single
    /// characters as standalone text runs; merging keeps the token stream
    /// equal to the untouched source text.
    static func mergeAdjacentText(_ parts: [MarkdownInlineToken]) -> [MarkdownInlineToken] {
        var merged: [MarkdownInlineToken] = []
        for part in parts {
            if case .text(let value) = part,
               case .text(let previous)? = merged.last {
                merged[merged.count - 1] = .text(previous + value)
            } else {
                merged.append(part)
            }
        }
        return merged
    }

    static func captureGroups(_ s: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: range) else { return [] }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: s) {
                groups.append(String(s[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    /// Replace common LaTeX symbols with their Unicode equivalents.
    static func resolveLaTeXSymbols(_ s: String) -> String {
        let symbols = [
            "\\rightarrow": "→",
            "\\leftarrow": "←",
            "\\Rightarrow": "⇒",
            "\\Leftarrow": "⇐",
            "\\leftrightarrow": "↔",
            "\\implies": "⟹",
            "\\approx": "≈",
            "\\neq": "≠",
            "\\le": "≤",
            "\\ge": "≥",
            "\\alpha": "α",
            "\\beta": "β",
            "\\gamma": "γ",
            "\\delta": "δ",
            "\\epsilon": "ε",
            "\\theta": "θ",
            "\\lambda": "λ",
            "\\mu": "μ",
            "\\pi": "π",
            "\\sigma": "σ",
            "\\phi": "φ",
            "\\omega": "ω",
            "\\infty": "∞",
            "\\sum": "∑",
            "\\int": "∫",
            "\\nabla": "∇",
            "\\partial": "∂"
        ]
        var result = s
        for (latex, unicode) in symbols {
            result = result.replacingOccurrences(of: latex, with: unicode)
        }
        return result
    }
}

extension MarkdownDocumentParser {
    /// Detects `$$ … $$` (same line, or spanning lines) and `\[…\]` display
    /// math, consuming the block and returning its raw LaTeX body.
    static func mathBlock(_ lines: [String], at i: inout Int) -> String? {
        guard i < lines.count, isMathBlockStart(lines[i]) else { return nil }
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

        if trimmed == "$$" {
            var body: [String] = []
            var j = i + 1
            var closed = false
            while j < lines.count {
                if lines[j].trimmingCharacters(in: .whitespaces) == "$$" {
                    closed = true
                    j += 1
                    break
                }
                body.append(lines[j])
                j += 1
            }
            guard closed else { return nil }
            i = j
            return body.joined(separator: "\n")
        }

        if trimmed.hasPrefix("\\[") {
            if trimmed.hasSuffix("\\]"), trimmed.count > 4 {
                i += 1
                return String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
            }
            var body: [String] = []
            let first = String(trimmed.hasSuffix("\\\\") ? trimmed : trimmed)
            if first.count > 2 { body.append(String(first.dropFirst(2))) }
            var j = i + 1
            var closed = false
            while j < lines.count {
                let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                if candidate.hasSuffix("\\]") {
                    let inner = String(candidate.dropLast(2))
                    if !inner.isEmpty { body.append(inner) }
                    closed = true
                    j += 1
                    break
                }
                body.append(lines[j])
                j += 1
            }
            guard closed else { return nil }
            i = j
            return body.joined(separator: "\n")
        }

        // $$E = mc^2$$ on a single line.
        if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 4 {
            i += 1
            return String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func isMathBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "$$" { return true }
        if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 4 { return true }
        if trimmed == "\\[" || (trimmed.hasPrefix("\\[") && trimmed.count > 2) { return true }
        return false
    }
}

