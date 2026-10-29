import AppKit
import SwiftUI

/// One classified run of source code.
struct CodeToken: Equatable {
    let text: String
    let kind: CodeTokenKind
}

/// Language-aware tokenizer used by the chat code spoiler and by the
/// markdown renderer. It is intentionally a lexer, not a compiler: it
/// recognises comments, strings, numbers, keywords, declarations and calls
/// well enough to colour code the way the configured theme promises, while
/// never altering the source text (`tokens.map(\.text).joined() == code`).
enum CodeSyntaxHighlighter {

    // MARK: - Public API

    /// True for explicit diff/patch blocks and for any block whose lines carry
    /// unified-diff markers — same rule the old SwiftUI renderer used.
    static func isDiff(code: String, language: String) -> Bool {
        let lower = language.lowercased()
        if lower == "diff" || lower == "patch" { return true }
        return code.components(separatedBy: "\n").contains { line in
            line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@")
                || line.hasPrefix("diff --git") || line.hasPrefix("index ")
        }
    }

    static func tokenize(_ code: String, language: String) -> [CodeToken] {
        guard !code.isEmpty else { return [] }
        if isDiff(code: code, language: language) {
            return diffTokens(code)
        }

        let profile = SyntaxProfile(language: language)
        let chars = Array(code)
        var tokens: [CodeToken] = []
        var plain = ""
        var index = 0
        var pendingDeclaration: CodeTokenKind?

        func flushPlain() {
            guard !plain.isEmpty else { return }
            tokens.append(CodeToken(text: plain, kind: .text))
            plain = ""
        }

        func emit(_ text: String, _ kind: CodeTokenKind) {
            flushPlain()
            tokens.append(CodeToken(text: text, kind: kind))
        }

        func starts(with marker: String, at position: Int) -> Bool {
            let markerChars = Array(marker)
            guard position + markerChars.count <= chars.count else { return false }
            for offset in 0..<markerChars.count where chars[position + offset] != markerChars[offset] {
                return false
            }
            return true
        }

        func consumeString(from start: Int, quote: Character) -> Int {
            let triple = profile.tripleQuotes
                && starts(with: String(repeating: quote, count: 3), at: start)
            var cursor = start + (triple ? 3 : 1)
            while cursor < chars.count {
                let character = chars[cursor]
                if profile.escapesStrings && character == "\\" {
                    cursor = min(cursor + 2, chars.count)
                    continue
                }
                if triple {
                    if character == quote,
                       cursor + 2 < chars.count,
                       chars[cursor + 1] == quote,
                       chars[cursor + 2] == quote {
                        return cursor + 3
                    }
                } else {
                    if character == quote { return cursor + 1 }
                    if character == "\n" { return cursor }
                }
                cursor += 1
            }
            return chars.count
        }

        func consumeUntil(_ markers: [String], from start: Int) -> Int? {
            var cursor = start
            while cursor < chars.count {
                if markers.contains(where: { starts(with: $0, at: cursor) }) {
                    return cursor
                }
                cursor += 1
            }
            return nil
        }

        while index < chars.count {
            let character = chars[index]

            // Comments ------------------------------------------------------
            if let marker = profile.lineComments.first(where: { starts(with: $0, at: index) }) {
                let start = index
                index += marker.count
                while index < chars.count && chars[index] != "\n" { index += 1 }
                emit(String(chars[start..<index]), .comment)
                continue
            }

            if profile.blockComment, starts(with: "/*", at: index) {
                let start = index
                if let end = consumeUntil(["*/"], from: index + 2) {
                    index = min(end + 2, chars.count)
                } else {
                    index = chars.count
                }
                emit(String(chars[start..<index]), .comment)
                continue
            }

            if profile.htmlComment, starts(with: "<!--", at: index) {
                let start = index
                if let end = consumeUntil(["-->"], from: index + 4) {
                    index = min(end + 3, chars.count)
                } else {
                    index = chars.count
                }
                emit(String(chars[start..<index]), .comment)
                continue
            }

            // Strings -------------------------------------------------------
            let isRawPrefix = profile.stringPrefixes.contains(character)
                && index + 1 < chars.count
                && profile.quotes.contains(chars[index + 1])
            if profile.quotes.contains(character) || isRawPrefix {
                let start = index
                var cursor = index
                if isRawPrefix { cursor += 1 }
                index = consumeString(from: cursor, quote: chars[cursor])
                emit(String(chars[start..<index]), .string)
                continue
            }

            // Decorators / attributes --------------------------------------
            if character == "@", profile.decorators, index + 1 < chars.count,
               isIdentifierStart(chars[index + 1]) {
                let start = index
                index += 1
                while index < chars.count && isIdentifierBody(chars[index]) { index += 1 }
                while index + 1 < chars.count && chars[index] == "." && isIdentifierStart(chars[index + 1]) {
                    index += 1
                    while index < chars.count && isIdentifierBody(chars[index]) { index += 1 }
                }
                emit(String(chars[start..<index]), .decorator)
                continue
            }

            // Numbers -------------------------------------------------------
            if character.isNumber {
                let start = index
                while index < chars.count {
                    let next = chars[index]
                    if next.isLetter || next.isNumber || next == "." || next == "_" {
                        index += 1
                    } else if (next == "+" || next == "-"),
                              index > start,
                              chars[index - 1] == "e" || chars[index - 1] == "E" {
                        index += 1
                    } else {
                        break
                    }
                }
                emit(String(chars[start..<index]), .number)
                continue
            }

            // Identifiers ---------------------------------------------------
            if isIdentifierStart(character) {
                let start = index
                while index < chars.count && isIdentifierBody(chars[index]) { index += 1 }
                let word = String(chars[start..<index])
                let normalized = profile.caseInsensitiveKeywords ? word.lowercased() : word

                if let declaration = pendingDeclaration {
                    pendingDeclaration = nil
                    emit(word, declaration)
                    continue
                }

                if profile.keywords.contains(normalized) {
                    if let declaration = profile.declarations[normalized] {
                        pendingDeclaration = declaration
                    }
                    emit(word, .keyword)
                    continue
                }

                if profile.constants.contains(normalized.lowercased()) {
                    emit(word, .constant)
                    continue
                }

                if profile.builtins.contains(normalized)
                    || profile.builtins.contains(normalized.lowercased()) {
                    emit(word, .function)
                    continue
                }

                var cursor = index
                while cursor < chars.count && chars[cursor].isWhitespace { cursor += 1 }
                if cursor < chars.count && chars[cursor] == "(" {
                    emit(word, .function)
                    continue
                }

                if let first = word.first, first.isUppercase {
                    emit(word, .type)
                    continue
                }

                plain += word
                continue
            }

            plain.append(character)
            index += 1
        }

        flushPlain()
        return tokens
    }

    static func attributed(_ code: String, language: String, palette: CodePalette) -> AttributedString {
        var result = AttributedString()
        for token in tokenize(code, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = palette.color(for: token.kind)
            result.append(piece)
        }
        return result
    }

    static func nsAttributed(
        _ code: String,
        language: String,
        palette: CodePalette,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        for token in tokenize(code, language: language) {
            result.append(NSAttributedString(string: token.text, attributes: [
                .font: font,
                .foregroundColor: NSColor(palette.color(for: token.kind))
            ]))
        }
        return result
    }

    // MARK: - Diff

    private static func diffTokens(_ code: String) -> [CodeToken] {
        let lines = code.components(separatedBy: "\n")
        var tokens: [CodeToken] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                tokens.append(CodeToken(text: "\n", kind: .text))
            }
            let kind: CodeTokenKind
            if line.hasPrefix("@@") || line.hasPrefix("diff --git") || line.hasPrefix("index ")
                || line.hasPrefix("+++") || line.hasPrefix("---") {
                kind = .diffMeta
            } else if line.hasPrefix("+") {
                kind = .diffAdded
            } else if line.hasPrefix("-") {
                kind = .diffRemoved
            } else {
                kind = .text
            }
            tokens.append(CodeToken(text: line, kind: kind))
        }
        return tokens
    }

    // MARK: - Character helpers

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private static func isIdentifierBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }
}

// MARK: - Language profiles

private struct SyntaxProfile {
    var lineComments: [String] = []
    var blockComment = false
    var htmlComment = false
    var tripleQuotes = false
    var escapesStrings = true
    var quotes: Set<Character> = ["\"", "'"]
    var stringPrefixes: Set<Character> = []
    var decorators = false
    var caseInsensitiveKeywords = false
    var keywords: Set<String> = []
    var builtins: Set<String> = []
    var constants: Set<String> = [
        "true", "false", "null", "nil", "none", "undefined", "nan", "infinity",
        "this", "self", "super", "cls"
    ]
    var declarations: [String: CodeTokenKind] = [:]

    init(language: String) {
        let lower = language.lowercased()
        switch lower {
        case "python", "py", "python3":
            configurePython()
        case "swift":
            configureSwift()
        case "javascript", "js", "jsx", "typescript", "ts", "tsx", "node":
            configureJavaScript(lower.hasPrefix("t"))
        case "bash", "sh", "shell", "zsh", "console", "shellscript":
            configureShell()
        case "json", "jsonc":
            configureJSON()
        case "sql", "mysql", "postgresql", "postgres", "sqlite":
            configureSQL()
        case "go", "golang":
            configureGo()
        case "rust", "rs":
            configureRust()
        case "java", "kotlin", "kt", "c", "cpp", "c++", "csharp", "cs", "objc":
            configureCLike()
        case "html", "htm", "xml", "xhtml", "svg":
            configureMarkup()
        case "css", "scss", "sass", "less":
            configureCSS()
        default:
            // Unknown fence language: still colour comments, strings and
            // numbers with the common C-like rules rather than showing a
            // completely flat block.
            configureCLike()
        }
    }

    private mutating func configurePython() {
        lineComments = ["#"]
        tripleQuotes = true
        quotes = ["\"", "'"]
        stringPrefixes = ["r", "R", "f", "F", "b", "B", "u", "U"]
        decorators = true
        keywords = [
            "and", "as", "assert", "async", "await", "break", "class", "continue",
            "def", "del", "elif", "else", "except", "finally", "for", "from",
            "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
            "or", "pass", "raise", "return", "try", "while", "with", "yield",
            "match", "case"
        ]
        builtins = [
            "print", "len", "range", "str", "int", "float", "bool", "list", "dict",
            "set", "tuple", "frozenset", "bytes", "bytearray", "open", "sum", "min",
            "max", "abs", "round", "sorted", "reversed", "enumerate", "zip", "map",
            "filter", "any", "all", "isinstance", "issubclass", "type", "id",
            "input", "repr", "format", "getattr", "setattr", "hasattr", "delattr",
            "iter", "next", "vars", "dir", "help", "hash", "hex", "oct", "bin",
            "ord", "chr", "exec", "eval", "compile", "globals", "locals", "property",
            "staticmethod", "classmethod", "object"
        ]
        declarations = ["def": .function, "class": .type]
    }

    private mutating func configureSwift() {
        lineComments = ["//"]
        blockComment = true
        quotes = ["\""]
        decorators = true
        keywords = [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
            "func", "import", "init", "inout", "internal", "let", "open", "operator",
            "private", "precedencegroup", "protocol", "public", "rethrows", "static",
            "struct", "subscript", "typealias", "var", "break", "case", "catch",
            "continue", "default", "defer", "do", "else", "fallthrough", "for",
            "guard", "if", "in", "repeat", "return", "switch", "throw", "where",
            "while", "as", "any", "await", "is", "throws", "try", "some", "actor",
            "async"
        ]
        builtins = [
            "print", "abs", "min", "max", "zip", "map", "filter", "reduce", "sorted",
            "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set"
        ]
        declarations = [
            "func": .function, "class": .type, "struct": .type, "enum": .type,
            "protocol": .type, "extension": .type, "typealias": .type
        ]
    }

    private mutating func configureJavaScript(_ typescript: Bool) {
        lineComments = ["//"]
        blockComment = true
        quotes = ["\"", "'", "`"]
        decorators = true
        keywords = [
            "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "export", "extends",
            "finally", "for", "function", "if", "import", "in", "instanceof",
            "let", "new", "return", "static", "switch", "throw", "try", "typeof",
            "var", "void", "while", "with", "yield", "async", "of", "from", "get",
            "set", "as"
        ]
        if typescript {
            keywords.formUnion([
                "interface", "type", "enum", "implements", "private", "protected",
                "public", "readonly", "declare", "namespace", "abstract", "satisfies",
                "keyof", "infer", "unknown", "never", "any", "string", "number",
                "boolean", "symbol", "bigint", "object"
            ])
        }
        builtins = [
            "console", "require", "module", "exports", "parseInt", "parseFloat",
            "isNaN", "isFinite", "setTimeout", "setInterval", "clearTimeout",
            "clearInterval", "fetch", "JSON", "Math", "Date", "Promise", "Map",
            "Set", "Array", "Object", "String", "Number", "Boolean", "Error"
        ]
        declarations = [
            "function": .function, "class": .type, "interface": .type, "type": .type,
            "enum": .type, "namespace": .type
        ]
    }

    private mutating func configureShell() {
        lineComments = ["#"]
        quotes = ["\"", "'", "`"]
        keywords = [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do",
            "done", "case", "esac", "function", "in", "select", "time", "coproc",
            "break", "continue", "return", "exit", "export", "local", "readonly",
            "declare", "typeset", "unset", "shift", "source", "alias", "unalias"
        ]
        builtins = [
            "echo", "printf", "cd", "pwd", "test", "read", "command", "type",
            "hash", "umask", "wait", "trap", "set", "eval", "exec",
            // Frequently used external commands; colouring them makes a shell
            // example readable instead of leaving the whole line in body text.
            "curl", "wget", "git", "python", "python3", "pip", "pip3", "node",
            "npm", "npx", "yarn", "pnpm", "ls", "cat", "head", "tail", "grep",
            "sed", "awk", "find", "xargs", "sort", "uniq", "wc", "cut", "tr",
            "mkdir", "rmdir", "rm", "cp", "mv", "ln", "touch", "chmod", "chown",
            "sudo", "apt", "apt-get", "brew", "docker", "podman", "make", "cmake",
            "swift", "xcodebuild", "sqlite3", "psql", "mysql", "redis-cli", "jq",
            "tar", "gzip", "unzip", "zip", "ssh", "scp", "rsync", "kill", "ps",
            "env", "which", "open", "defaults", "launchctl"
        ]
    }

    private mutating func configureJSON() {
        quotes = ["\""]
        stringPrefixes = []
        keywords = []
        builtins = []
    }

    private mutating func configureSQL() {
        lineComments = ["--"]
        blockComment = true
        quotes = ["'", "\""]
        caseInsensitiveKeywords = true
        keywords = [
            "select", "from", "where", "insert", "into", "values", "update", "set",
            "delete", "create", "table", "drop", "alter", "add", "column", "index",
            "join", "inner", "left", "right", "outer", "full", "on", "group", "by",
            "order", "having", "limit", "offset", "union", "all", "distinct", "as",
            "and", "or", "not", "is", "in", "like", "between", "exists", "case",
            "when", "then", "else", "end", "begin", "commit", "rollback", "primary",
            "key", "foreign", "references", "default", "constraint", "unique",
            "view", "with", "asc", "desc"
        ]
        builtins = [
            "count", "sum", "avg", "min", "max", "coalesce", "cast", "now",
            "date", "round", "length", "substr", "upper", "lower"
        ]
        declarations = ["table": .type, "view": .type]
    }

    private mutating func configureGo() {
        lineComments = ["//"]
        blockComment = true
        quotes = ["\"", "'", "`"]
        keywords = [
            "break", "case", "chan", "const", "continue", "default", "defer",
            "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
            "interface", "map", "package", "range", "return", "select", "struct",
            "switch", "type", "var"
        ]
        builtins = [
            "append", "cap", "close", "complex", "copy", "delete", "imag", "len",
            "make", "new", "panic", "print", "println", "real", "recover",
            "string", "int", "float64", "bool", "byte", "rune", "error"
        ]
        declarations = ["func": .function, "type": .type, "struct": .type, "interface": .type]
    }

    private mutating func configureRust() {
        lineComments = ["//"]
        blockComment = true
        quotes = ["\"", "'"]
        keywords = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn",
            "else", "enum", "extern", "fn", "for", "if", "impl", "in", "let",
            "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
            "static", "struct", "super", "trait", "type", "unsafe", "use", "where",
            "while", "union"
        ]
        builtins = [
            "println", "print", "format", "vec", "panic", "assert", "assert_eq",
            "Some", "None", "Ok", "Err", "String", "Vec", "Box", "Option", "Result"
        ]
        declarations = ["fn": .function, "struct": .type, "enum": .type, "trait": .type, "impl": .type]
    }

    private mutating func configureCLike() {
        lineComments = ["//"]
        blockComment = true
        quotes = ["\"", "'"]
        keywords = [
            "auto", "break", "case", "catch", "char", "class", "const", "continue",
            "default", "delete", "do", "double", "else", "enum", "explicit",
            "extern", "final", "float", "for", "friend", "goto", "if", "inline",
            "int", "interface", "long", "namespace", "new", "operator", "override",
            "package", "private", "protected", "public", "register", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "template",
            "throw", "throws", "try", "typedef", "typename", "union", "unsigned",
            "using", "virtual", "void", "volatile", "while", "import", "extends",
            "implements", "abstract", "synchronized", "instanceof", "var", "fun",
            "val", "when", "object", "data", "sealed"
        ]
        builtins = [
            "printf", "println", "malloc", "free", "sizeof", "String", "System",
            "Math", "Integer", "Boolean", "List", "Map", "Set", "ArrayList",
            "HashMap"
        ]
        declarations = [
            "class": .type, "struct": .type, "enum": .type, "interface": .type,
            "namespace": .type, "typedef": .type
        ]
    }

    private mutating func configureMarkup() {
        htmlComment = true
        quotes = ["\"", "'"]
        keywords = []
        builtins = []
    }

    private mutating func configureCSS() {
        blockComment = true
        quotes = ["\"", "'"]
        keywords = []
        builtins = []
    }
}
