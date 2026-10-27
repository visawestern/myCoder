import Foundation

/// One declared symbol found in a source file.
struct SymbolDeclaration: Equatable {
    let name: String
    /// "func" | "type" | "var"
    let kind: String
    /// 1-based line of the declaration.
    let line: Int
}

/// A declaration with its real line span, used by the code graph so a tool can
/// return exactly the body it cites instead of guessing an end line.
struct SymbolBlock: Equatable {
    let name: String
    let kind: String
    let startLine: Int
    let endLine: Int
}

/// Extracts declared symbol names (functions, types, variables) from source
/// text. This is what lets the LOCAL model name real functions and variables
/// instead of guessing paths — the local model never writes code, it only
/// points at existing declarations (user directive D7).
///
/// The extraction is regex-based (no SwiftSyntax): it must stay fast enough to
/// run over every indexed file on the host, locally and for free.
enum SymbolNameExtractor {

    // MARK: - Public API

    static func declarations(in text: String, language: String) -> [SymbolDeclaration] {
        let rules = rules(for: language)
        guard !rules.isEmpty, !text.isEmpty else { return [] }
        let masked = mask(text, language: language)
        let lines = LineIndex(text: masked)
        let ns = masked as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var found: [SymbolDeclaration] = []
        var seen = Set<String>()
        for rule in rules {
            for match in rule.regex.matches(in: masked, options: [], range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let nameRange = match.range(at: 1)
                guard nameRange.location != NSNotFound else { continue }
                let name = ns.substring(with: nameRange)
                guard !name.isEmpty, !blockedNames.contains(name) else { continue }
                let key = "\(rule.kind):\(name):\(lines.line(at: nameRange.location))"
                guard seen.insert(key).inserted else { continue }
                found.append(SymbolDeclaration(
                    name: name,
                    kind: rule.kind,
                    line: lines.line(at: nameRange.location)
                ))
            }
        }
        return found.sorted {
            if $0.line != $1.line { return $0.line < $1.line }
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.name < $1.name
        }
    }

    /// Declarations with their real line span. The span is derived from the
    /// masked text, so a brace inside a string or comment never extends a
    /// block, and an unclosed block honestly stops at its declaration line.
    ///
    /// Braced languages use brace matching (an opening `{` must appear before
    /// the next declaration, otherwise the declaration has no body). Python
    /// uses indentation, because it has no braces to match.
    static func blocks(in text: String, language: String) -> [SymbolBlock] {
        let rules = rules(for: language)
        guard !rules.isEmpty, !text.isEmpty else { return [] }
        let masked = mask(text, language: language)
        let ns = masked as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let lines = LineIndex(text: masked)

        var raw: [(name: String, kind: String, matchStart: Int, matchEnd: Int, startLine: Int)] = []
        var seen = Set<String>()
        for rule in rules {
            for match in rule.regex.matches(in: masked, options: [], range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let nameRange = match.range(at: 1)
                guard nameRange.location != NSNotFound else { continue }
                let name = ns.substring(with: nameRange)
                guard !name.isEmpty, !blockedNames.contains(name) else { continue }
                let startLine = lines.line(at: nameRange.location)
                let key = "\(rule.kind):\(name):\(startLine)"
                guard seen.insert(key).inserted else { continue }
                raw.append((
                    name: name,
                    kind: rule.kind,
                    matchStart: match.range.location,
                    matchEnd: match.range.location + match.range.length,
                    startLine: startLine
                ))
            }
        }
        raw.sort {
            if $0.matchStart != $1.matchStart { return $0.matchStart < $1.matchStart }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.kind < $1.kind
        }
        guard !raw.isEmpty else { return [] }

        if language == "python" {
            let split = masked.components(separatedBy: "\n")
            return raw.map { item in
                SymbolBlock(
                    name: item.name,
                    kind: item.kind,
                    startLine: item.startLine,
                    endLine: pythonBlockEnd(startLine: item.startLine, lines: split)
                )
            }
        }

        let braces = BraceMap(text: masked)
        var blocks: [SymbolBlock] = []
        for (index, item) in raw.enumerated() {
            // The opening brace must belong to THIS declaration, so it has to
            // appear before the next declaration starts. A protocol
            // requirement or a stored property has no brace and stays a
            // single line.
            let limit = index + 1 < raw.count ? raw[index + 1].matchStart : ns.length
            var endLine = item.startLine
            if let open = braces.firstOpen(from: item.matchEnd, before: limit),
               let close = braces.close(forOpen: open) {
                endLine = max(item.startLine, lines.line(at: close))
            }
            blocks.append(SymbolBlock(
                name: item.name,
                kind: item.kind,
                startLine: item.startLine,
                endLine: endLine
            ))
        }
        return blocks
    }

    /// Last line of a Python block: blank lines are part of it, and the block
    /// ends at the first non-blank line that is not indented deeper than the
    /// declaration.
    private static func pythonBlockEnd(startLine: Int, lines: [String]) -> Int {
        guard startLine >= 1, startLine <= lines.count else { return startLine }
        let base = indentation(of: lines[startLine - 1])
        var end = startLine
        var index = startLine
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            guard indentation(of: line) > base else { break }
            end = index + 1
            index += 1
        }
        return end
    }

    private static func indentation(of line: String) -> Int {
        var depth = 0
        for character in line {
            if character == " " { depth += 1 }
            else if character == "\t" { depth += 4 }
            else { break }
        }
        return depth
    }

    /// Matching `{` / `}` offsets over masked text. Attached string and block
    /// comment characters are blanked by `mask`, so they cannot join a pair.
    private struct BraceMap {
        private let opens: [Int]
        private let closes: [Int: Int]

        init(text: String) {
            let ns = text as NSString
            var stack: [Int] = []
            var openOffsets: [Int] = []
            var closeMap: [Int: Int] = [:]
            var index = 0
            while index < ns.length {
                let character = ns.character(at: index)
                if character == 0x7B {          // {
                    stack.append(index)
                    openOffsets.append(index)
                } else if character == 0x7D {   // }
                    if let open = stack.popLast() {
                        closeMap[open] = index
                    }
                }
                index += 1
            }
            self.opens = openOffsets
            self.closes = closeMap
        }

        /// First opening brace at or after `offset`, and strictly before
        /// `limit`. Binary search keeps this O(log n) per declaration.
        func firstOpen(from offset: Int, before limit: Int) -> Int? {
            guard !opens.isEmpty, offset < limit else { return nil }
            var low = 0
            var high = opens.count
            while low < high {
                let mid = (low + high) / 2
                if opens[mid] < offset { low = mid + 1 } else { high = mid }
            }
            guard low < opens.count, opens[low] < limit else { return nil }
            return opens[low]
        }

        func close(forOpen open: Int) -> Int? {
            closes[open]
        }
    }

    /// Names that look like declarations but never are useful to point at.
    private static let blockedNames: Set<String> = [
        "if", "for", "while", "switch", "catch", "return", "else", "do",
        "sizeof", "new", "delete", "throw", "case", "try", "using", "lock",
        "foreach", "select", "match", "where", "when", "guard", "defer",
    ]

    // MARK: - Rules

    private struct Rule {
        let kind: String
        let regex: NSRegularExpression
    }

    private static func rules(for language: String) -> [Rule] {
        let patterns: [(kind: String, pattern: String)]
        switch language {
        case "swift":
            // Attributes may precede declarations (`@Test`, `@MainActor`,
            // `@discardableResult`); without them every annotated symbol was
            // invisible to the graph.
            let attributes = #"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)\n]*\))?[ \t]+)*"#
            patterns = [
                ("func", #"^[ \t]*"# + attributes + #"(?:(?:public|private|internal|fileprivate|open|static|final|override|mutating|nonisolated|convenience|required)[ \t]+)*func[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*"# + attributes + #"(?:(?:public|private|internal|fileprivate|open|final)[ \t]+)*(?:class|struct|enum|protocol|actor|extension)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("var", #"^[ \t]*"# + attributes + #"(?:(?:public|private|internal|fileprivate|open|static|final|lazy|weak|unowned|override|nonisolated)[ \t]+)*(?:var|let)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#)
            ]
        case "python":
            patterns = [
                ("func", #"^[ \t]*def[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*class[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#)
            ]
        case "javascript", "typescript":
            patterns = [
                ("func", #"^[ \t]*(?:export[ \t]+)?(?:default[ \t]+)?(?:async[ \t]+)?function[ \t]*\*?[ \t]*([A-Za-z_$][A-Za-z0-9_$]*)"#),
                ("type", #"^[ \t]*(?:export[ \t]+)?(?:default[ \t]+)?(?:declare[ \t]+)?(?:abstract[ \t]+)?class[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)"#),
                ("type", #"^[ \t]*(?:export[ \t]+)?(?:declare[ \t]+)?interface[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)"#),
                ("type", #"^[ \t]*(?:export[ \t]+)?type[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)[ \t]*="#),
                ("var", #"^[ \t]*(?:export[ \t]+)?(?:const|let|var)[ \t]+([A-Za-z_$][A-Za-z0-9_$]*)"#)
            ]
        case "go":
            patterns = [
                ("func", #"^[ \t]*func[ \t]+(?:\([^)]*\)[ \t]*)?([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*type[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+(?:struct|interface)"#)
            ]
        case "rust":
            patterns = [
                ("func", #"^[ \t]*(?:pub(?:\([^)]*\))?[ \t]+)?(?:async[ \t]+)?(?:unsafe[ \t]+)?fn[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*(?:pub(?:\([^)]*\))?[ \t]+)?(?:struct|enum|trait|union)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*(?:pub(?:\([^)]*\))?[ \t]+)?type[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#)
            ]
        case "java", "c", "cpp":
            patterns = [
                ("type", #"^[ \t]*(?:(?:public|private|protected|static|final|abstract|sealed)[ \t]+)*class[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("type", #"^[ \t]*(?:typedef[ \t]+)?struct[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#),
                ("func", #"^[ \t]*(?:(?:public|private|protected|static|final|abstract|synchronized|native|default|virtual|inline|extern)[ \t]+)*(?:[A-Za-z_][A-Za-z0-9_]*(?:<[^>{}()]*>)?[ \t]*\*?[ \t]*)([A-Za-z_][A-Za-z0-9_]*)[ \t]*\("#)
            ]
        default:
            patterns = []
        }
        return patterns.compactMap { kind, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                return nil
            }
            return Rule(kind: kind, regex: regex)
        }
    }

    // MARK: - Masking (comments and strings keep their line numbers)

    /// Comment/string-free view of the source. Call extraction needs the same
    /// masking as symbol extraction, so a call-looking word inside a string or
    /// comment is never recorded as an edge.
    static func maskedText(_ text: String, language: String) -> String {
        mask(text, language: language)
    }

    /// Replaces comment and string contents with spaces so a declaration
    /// mentioned inside a comment or a string literal is not reported.
    /// Newlines are preserved, so line numbers of real code do not shift.
    private static func mask(_ text: String, language: String) -> String {
        let chars = Array(text)
        guard !chars.isEmpty else { return text }
        var out = chars
        let lineTokens = lineCommentTokens(for: language)
        let blockTokens = blockCommentTokens(for: language)
        let quotes = quoteCharacters(for: language)
        let tripleQuoted = language == "python"

        var index = 0
        let count = chars.count
        while index < count {
            let character = chars[index]
            if character == "\n" {
                index += 1
                continue
            }
            // Block comment.
            if let token = blockTokens.first(where: { matches(chars, at: index, token: $0.0) }) {
                let end = find(chars, from: index + token.0.count, token: token.1) ?? count
                blank(&out, from: index, to: end)
                index = end
                continue
            }
            // Line comment.
            if let token = lineTokens.first(where: { matches(chars, at: index, token: $0) }) {
                var end = index
                while end < count && chars[end] != "\n" { end += 1 }
                blank(&out, from: index, to: end)
                index = end
                continue
            }
            // Triple-quoted string (python).
            if tripleQuoted,
               let token = ["\"\"\"", "'''"].first(where: { matches(chars, at: index, token: $0) }) {
                var end = index + token.count
                while end < count && !matches(chars, at: end, token: token) { end += 1 }
                end = min(end + token.count, count)
                blank(&out, from: index, to: end)
                index = end
                continue
            }
            // Single-line string.
            if quotes.contains(character) {
                var end = index + 1
                while end < count && chars[end] != "\n" {
                    if chars[end] == "\\" {
                        end += 2
                        continue
                    }
                    if chars[end] == character {
                        end += 1
                        break
                    }
                    end += 1
                }
                let stop = min(end, count)
                blank(&out, from: index, to: stop)
                index = stop
                continue
            }
            index += 1
        }
        return String(out)
    }

    private static func lineCommentTokens(for language: String) -> [String] {
        switch language {
        case "swift", "javascript", "typescript", "java", "c", "cpp", "go", "rust":
            return ["//"]
        case "python", "shell", "yaml", "ruby":
            return ["#"]
        default:
            return []
        }
    }

    private static func blockCommentTokens(for language: String) -> [(String, String)] {
        switch language {
        case "swift", "javascript", "typescript", "java", "c", "cpp", "go", "rust":
            return [("/*", "*/")]
        default:
            return []
        }
    }

    private static func quoteCharacters(for language: String) -> Set<Character> {
        switch language {
        case "python", "javascript", "typescript", "rust":
            return ["\"", "'"]
        case "swift", "java", "c", "cpp", "go":
            return ["\""]
        default:
            return []
        }
    }

    private static func matches(_ chars: [Character], at index: Int, token: String) -> Bool {
        let tokenChars = Array(token)
        guard index + tokenChars.count <= chars.count else { return false }
        for offset in 0..<tokenChars.count where chars[index + offset] != tokenChars[offset] {
            return false
        }
        return true
    }

    private static func find(_ chars: [Character], from start: Int, token: String) -> Int? {
        var index = start
        while index < chars.count {
            if matches(chars, at: index, token: token) { return index }
            index += 1
        }
        return nil
    }

    private static func blank(_ chars: inout [Character], from start: Int, to end: Int) {
        var index = max(0, start)
        let stop = min(end, chars.count)
        while index < stop {
            if chars[index] != "\n" { chars[index] = " " }
            index += 1
        }
    }

    // MARK: - Line index

    /// Maps UTF-16 offsets to 1-based line numbers.
    private struct LineIndex {
        private let starts: [Int]

        init(text: String) {
            var values: [Int] = [0]
            let ns = text as NSString
            var index = 0
            while index < ns.length {
                let character = ns.character(at: index)
                if character == 0x0A {
                    values.append(index + 1)
                }
                index += 1
            }
            starts = values
        }

        func line(at offset: Int) -> Int {
            var low = 0
            var high = starts.count - 1
            var result = 1
            while low <= high {
                let mid = (low + high) / 2
                if starts[mid] <= offset {
                    result = mid + 1
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return result
        }
    }
}
