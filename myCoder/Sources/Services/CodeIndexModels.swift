import Foundation

/// What a directed edge in the code graph means. Every edge is one of these —
/// there is no free-form "related" relation, so the graph can only state facts
/// it extracted from source.
enum CodeEdgeKind: String, Codable, CaseIterable, Sendable {
    /// file → symbol: this file declares the symbol.
    case declares
    /// symbol → symbol: a type/extension contains a member.
    case contains
    /// symbol/file → symbol: source calls the callee.
    case calls
    /// file → file: one file imports another project file.
    case imports
    /// test symbol/file → production symbol: a test exercises it.
    case tests
}

/// How strongly an edge is supported by source.
///
/// `exact` — resolved unambiguously, or the call/import was found verbatim.
/// `heuristic` — more than one candidate exists and the chosen one follows a
/// documented convention; it is labelled and never presented as a fact.
/// `unresolved` — the target is outside the indexed project (or the name is
/// ambiguous beyond a convention). These are produced for diagnostics and are
/// never persisted, so they can never reach evidence.
enum CodeEdgeConfidence: String, Codable, CaseIterable, Sendable {
    case exact
    case heuristic
    case unresolved

    var rank: Int {
        switch self {
        case .exact: return 2
        case .heuristic: return 1
        case .unresolved: return 0
        }
    }
}

/// Stable node ids shared by every edge and by the tools. File nodes use
/// `file:<path>`; symbol nodes embed everything needed to find the row again.
enum CodeNode {
    static func file(_ path: String) -> String {
        "file:\(path)"
    }

    static func filePath(of nodeID: String) -> String? {
        guard nodeID.hasPrefix("file:") else { return nil }
        return String(nodeID.dropFirst("file:".count))
    }
}

struct CodeSymbol: Codable, Equatable, Sendable {
    /// Project-relative path.
    let path: String
    let name: String
    /// "func" | "type" | "var"
    let kind: String
    /// 1-based, inclusive.
    let startLine: Int
    /// 1-based, inclusive.
    let endLine: Int

    var id: String {
        CodeSymbol.makeID(path: path, kind: kind, name: name, startLine: startLine)
    }

    static func makeID(path: String, kind: String, name: String, startLine: Int) -> String {
        "symbol:\(path)#\(kind):\(name)@\(startLine)"
    }
}

struct CodeEdge: Codable, Equatable, Sendable {
    let from: String
    let to: String
    let kind: CodeEdgeKind
    let confidence: CodeEdgeConfidence
}

/// A call found in source, before it is resolved against the project. The
/// caller is the innermost symbol containing the call site, or nil when the
/// call happens at file scope.
struct CodeRawCall: Codable, Equatable, Sendable {
    let callerID: String?
    let callee: String
    let line: Int
}

struct CodeRawImport: Codable, Equatable, Sendable {
    let module: String
    let line: Int
}

/// Everything the graph needs from one file. This is also what is persisted,
/// so a global edge rebuild never has to re-read the disk.
struct CodeFileExtraction: Codable, Equatable, Sendable {
    let path: String
    let language: String
    let symbols: [CodeSymbol]
    let imports: [CodeRawImport]
    let calls: [CodeRawCall]
}

// MARK: - Extraction

enum CodeIndexExtractor {

    /// Call-shaped words that are language syntax, not symbols. A cap keeps a
    /// generated file from flooding the graph.
    private static let ignoredCallNames: Set<String> = [
        "if", "for", "while", "switch", "catch", "guard", "return", "func",
        "init", "deinit", "subscript", "print", "super", "self", "new",
        "sizeof", "typeof", "await", "try", "throw", "in", "is", "as",
        "case", "where", "when", "match", "do", "else", "repeat", "defer"
    ]

    static let maxSymbolsPerFile = 500

    static func extract(path: String, text: String, language: String) -> CodeFileExtraction {
        let blocks = Array(SymbolNameExtractor.blocks(in: text, language: language)
            .prefix(maxSymbolsPerFile))
        let symbols = blocks.map {
            CodeSymbol(
                path: path,
                name: $0.name,
                kind: $0.kind,
                startLine: $0.startLine,
                endLine: $0.endLine
            )
        }
        return CodeFileExtraction(
            path: path,
            language: language,
            symbols: symbols,
            imports: imports(in: text, language: language),
            calls: calls(in: text, language: language, symbols: symbols)
        )
    }

    /// A path is a test when the layout or the filename says so. This decides
    /// only whether `tests` edges are emitted; it never hides a file from
    /// search.
    static func isTestPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        if components.contains(where: { ["Tests", "tests", "test", "__tests__", "spec"].contains($0) }) {
            return true
        }
        let base = (path as NSString).lastPathComponent.lowercased()
        if base.hasSuffix("tests.swift") || base.hasSuffix("_test.go")
            || base.hasSuffix(".test.ts") || base.hasSuffix(".spec.ts")
            || base.hasSuffix(".test.js") || base.hasSuffix(".spec.js")
            || base.hasSuffix(".test.tsx") || base.hasSuffix(".spec.tsx") {
            return true
        }
        if base.hasPrefix("test_") && base.hasSuffix(".py") { return true }
        return false
    }

    // MARK: Calls

    private static func calls(in text: String,
                              language: String,
                              symbols: [CodeSymbol]) -> [CodeRawCall] {
        guard !symbols.isEmpty else { return [] }
        let masked = SymbolNameExtractor.maskedText(text, language: language)
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_][A-Za-z0-9_]*)[ \t]*\("#
        ) else { return [] }
        let ns = masked as NSString
        let lines = SourceLineMap(text: masked)
        let declarations = Set(symbols.map { "\($0.name)|\($0.startLine)" })
        var seen = Set<String>()
        var calls: [CodeRawCall] = []

        for match in regex.matches(in: masked, options: [], range: NSRange(location: 0, length: ns.length)) {
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            let name = ns.substring(with: nameRange)
            guard !name.isEmpty, !ignoredCallNames.contains(name) else { continue }
            let line = lines.line(at: nameRange.location)
            // The declaration itself is not a call.
            guard !declarations.contains("\(name)|\(line)") else { continue }
            if precededByFuncKeyword(ns: ns, at: nameRange.location) { continue }

            let caller = innermostSymbol(symbols, containing: line)
            let key = "\(caller?.id ?? "file")|\(name)"
            guard seen.insert(key).inserted else { continue }
            calls.append(CodeRawCall(callerID: caller?.id, callee: name, line: line))
        }
        return calls
    }

    private static func precededByFuncKeyword(ns: NSString, at offset: Int) -> Bool {
        let start = max(0, offset - 12)
        let prefix = ns.substring(with: NSRange(location: start, length: offset - start))
        return prefix.hasSuffix("func ") || prefix.hasSuffix("func\t")
    }

    private static func innermostSymbol(_ symbols: [CodeSymbol], containing line: Int) -> CodeSymbol? {
        var best: CodeSymbol?
        var bestSpan = Int.max
        for symbol in symbols where symbol.startLine <= line && line <= symbol.endLine {
            let span = symbol.endLine - symbol.startLine
            if span < bestSpan
                || (span == bestSpan && symbol.startLine > (best?.startLine ?? -1)) {
                best = symbol
                bestSpan = span
            }
        }
        return best
    }

    // MARK: Imports

    private static func imports(in text: String, language: String) -> [CodeRawImport] {
        let patterns: [String]
        switch language {
        case "swift":
            patterns = [#"^[ \t]*(?:@testable[ \t]+)?import[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#]
        case "javascript", "typescript":
            patterns = [
                #"^[ \t]*import[ \t]+(?:[^'"]*?[ \t]+from[ \t]+)?['"]([^'"]+)['"]"#,
                #"^[ \t]*(?:const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*require\([ \t]*['"]([^'"]+)['"]"#
            ]
        case "python":
            patterns = [
                #"^[ \t]*from[ \t]+([A-Za-z_.][A-Za-z0-9_.]*)[ \t]+import"#,
                #"^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_.]*)"#
            ]
        case "go":
            patterns = [#"^[ \t]*import[ \t]+(?:[A-Za-z_.][A-Za-z0-9_.]*[ \t]+)?[`"]([^`"]+)[`"]"#]
        case "rust":
            patterns = [#"^[ \t]*use[ \t]+([A-Za-z_][A-Za-z0-9_:]*)"#]
        case "java":
            patterns = [#"^[ \t]*import[ \t]+(?:static[ \t]+)?([A-Za-z_][A-Za-z0-9_.]*)"#]
        case "c", "cpp":
            patterns = [#"^[ \t]*#[ \t]*include[ \t]+[<"]([^>"]+)[>"]"#]
        case "ruby":
            patterns = [#"^[ \t]*require(?:_relative)?[ \t]+['"]([^'"]+)['"]"#]
        default:
            patterns = []
        }
        guard !patterns.isEmpty else { return [] }

        let ns = text as NSString
        let lines = SourceLineMap(text: text)
        var result: [CodeRawImport] = []
        var seen = Set<String>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { continue }
                let module = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
                guard !module.isEmpty, seen.insert(module).inserted else { continue }
                result.append(CodeRawImport(module: module, line: lines.line(at: range.location)))
            }
        }
        return result
    }
}

/// Maps UTF-16 offsets to 1-based line numbers with a binary search, so call
/// extraction does not rescan the file per call.
struct SourceLineMap {
    private let starts: [Int]

    init(text: String) {
        var values: [Int] = [0]
        let ns = text as NSString
        var index = 0
        while index < ns.length {
            if ns.character(at: index) == 0x0A {
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

// MARK: - Graph

/// Builds the whole graph from per-file extractions. Pure and deterministic:
/// the same inputs always produce the same edges in the same order.
///
/// Resolution rules, in order: one candidate → exact; several candidates with
/// exactly one in the calling file → exact; several with no same-file winner →
/// heuristic to the first by path/line; none → unresolved.
enum CodeGraphBuilder {

    static func build(files: [CodeFileExtraction]) -> [CodeEdge] {
        let files = files.sorted { $0.path < $1.path }
        let allSymbols = files.flatMap(\.symbols)
        var byName: [String: [CodeSymbol]] = [:]
        for symbol in allSymbols {
            byName[symbol.name.lowercased(), default: []].append(symbol)
        }
        var symbolByID: [String: CodeSymbol] = [:]
        for symbol in allSymbols { symbolByID[symbol.id] = symbol }

        var edges: [CodeEdge] = []

        // declares
        for file in files {
            for symbol in file.symbols {
                edges.append(CodeEdge(
                    from: CodeNode.file(file.path),
                    to: symbol.id,
                    kind: .declares,
                    confidence: .exact
                ))
            }
        }

        // contains — direct parent only (smallest enclosing type).
        for file in files {
            let types = file.symbols.filter { $0.kind == "type" }
            for symbol in file.symbols {
                let parents = types.filter {
                    $0.id != symbol.id
                        && $0.startLine <= symbol.startLine
                        && symbol.endLine <= $0.endLine
                }.sorted {
                    let left = $0.endLine - $0.startLine
                    let right = $1.endLine - $1.startLine
                    if left != right { return left < right }
                    return $0.startLine < $1.startLine
                }
                guard let parent = parents.first else { continue }
                edges.append(CodeEdge(
                    from: parent.id,
                    to: symbol.id,
                    kind: .contains,
                    confidence: .exact
                ))
            }
        }

        // calls
        for file in files {
            for call in file.calls {
                let from = call.callerID ?? CodeNode.file(file.path)
                let candidates = byName[call.callee.lowercased()] ?? []
                let resolved: (String, CodeEdgeConfidence)
                if candidates.isEmpty {
                    resolved = ("unresolved:\(call.callee)", .unresolved)
                } else if candidates.count == 1 {
                    resolved = (candidates[0].id, .exact)
                } else {
                    let sameFile = candidates.filter { $0.path == file.path }
                    if sameFile.count == 1 {
                        resolved = (sameFile[0].id, .exact)
                    } else {
                        resolved = (candidates.sorted(by: symbolOrder)[0].id, .heuristic)
                    }
                }
                edges.append(CodeEdge(
                    from: from,
                    to: resolved.0,
                    kind: .calls,
                    confidence: resolved.1
                ))
            }
        }

        // imports
        let paths = Set(files.map(\.path))
        for file in files {
            for raw in file.imports {
                let resolution = resolveImport(raw.module, from: file.path, projectPaths: paths)
                guard let target = resolution.0 else { continue }
                edges.append(CodeEdge(
                    from: CodeNode.file(file.path),
                    to: CodeNode.file(target),
                    kind: .imports,
                    confidence: resolution.1
                ))
            }
        }

        // tests — exact when a test symbol really calls a production symbol.
        for edge in edges where edge.kind == .calls && edge.confidence != .unresolved {
            guard let target = symbolByID[edge.to], !CodeIndexExtractor.isTestPath(target.path) else {
                continue
            }
            let fromPath = symbolByID[edge.from]?.path ?? CodeNode.filePath(of: edge.from)
            guard let fromPath, CodeIndexExtractor.isTestPath(fromPath) else { continue }
            edges.append(CodeEdge(
                from: edge.from,
                to: edge.to,
                kind: .tests,
                confidence: .exact
            ))
        }

        // tests — heuristic from the `testFoo` naming convention. Only a
        // unique production symbol may receive it; an ambiguous name is not
        // guessed at.
        let production = allSymbols.filter { !CodeIndexExtractor.isTestPath($0.path) }
        for file in files where CodeIndexExtractor.isTestPath(file.path) {
            for testSymbol in file.symbols where testSymbol.kind == "func" {
                guard let token = testToken(testSymbol.name) else { continue }
                let matches = production.filter { symbol in
                    let normalized = normalizeName(symbol.name)
                    return normalized.count >= 3 && token.contains(normalized)
                }
                guard matches.count == 1, let target = matches.first else { continue }
                let alreadyExact = edges.contains {
                    $0.kind == .tests && $0.from == testSymbol.id && $0.to == target.id
                }
                guard !alreadyExact else { continue }
                edges.append(CodeEdge(
                    from: testSymbol.id,
                    to: target.id,
                    kind: .tests,
                    confidence: .heuristic
                ))
            }
        }

        return dedupe(edges)
    }

    /// Project-relative import resolution. `..` never escapes the project: a
    /// path that tries is treated as unresolved instead of linking outside it.
    static func resolveImport(_ module: String,
                              from path: String,
                              projectPaths: Set<String>) -> (String?, CodeEdgeConfidence) {
        let module = module.trimmingCharacters(in: .whitespaces)
        guard !module.isEmpty else { return (nil, .unresolved) }
        let extensions = ["", ".swift", ".py", ".ts", ".tsx", ".js", ".mjs", ".cjs",
                          ".go", ".rs", ".java", ".c", ".h", ".cpp", ".hpp", ".rb",
                          "/__init__.py", "/index.ts", "/index.js"]

        if module.hasPrefix(".") {
            let base = (path as NSString).deletingLastPathComponent
            guard let joined = normalizeProjectPath(base.isEmpty ? module : "\(base)/\(module)") else {
                return (nil, .unresolved)
            }
            for suffix in extensions where projectPaths.contains(joined + suffix) {
                return (joined + suffix, .exact)
            }
            return (nil, .unresolved)
        }

        // Python/Java dotted modules: foo.bar → foo/bar.
        let dotted = module.replacingOccurrences(of: ".", with: "/")
        for suffix in extensions where projectPaths.contains(dotted + suffix) {
            return (dotted + suffix, .exact)
        }

        let last = module
            .split(whereSeparator: { $0 == "/" || $0 == "." || $0 == ":" })
            .last
            .map(String.init) ?? module
        guard !last.isEmpty else { return (nil, .unresolved) }
        let matches = projectPaths.filter {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension == last
        }.sorted()
        if matches.count == 1 { return (matches[0], .exact) }
        if matches.count > 1 { return (matches[0], .heuristic) }
        return (nil, .unresolved)
    }

    /// Normalizes `a/./b/../c` to `a/c`, and refuses to return a path that
    /// climbs above the project root.
    static func normalizeProjectPath(_ path: String) -> String? {
        var stack: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
            default:
                stack.append(String(component))
            }
        }
        return stack.isEmpty ? nil : stack.joined(separator: "/")
    }

    private static func testToken(_ name: String) -> String? {
        let lower = name.lowercased()
        guard lower.hasPrefix("test"), name.count > 4 else { return nil }
        let token = normalizeName(String(name.dropFirst(4)))
        return token.count >= 3 ? token : nil
    }

    private static func normalizeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func symbolOrder(_ left: CodeSymbol, _ right: CodeSymbol) -> Bool {
        if left.path != right.path { return left.path < right.path }
        if left.startLine != right.startLine { return left.startLine < right.startLine }
        if left.name != right.name { return left.name < right.name }
        return left.kind < right.kind
    }

    private static func dedupe(_ edges: [CodeEdge]) -> [CodeEdge] {
        var best: [String: CodeEdge] = [:]
        for edge in edges {
            let key = "\(edge.from)|\(edge.to)|\(edge.kind.rawValue)"
            if let existing = best[key], existing.confidence.rank >= edge.confidence.rank {
                continue
            }
            best[key] = edge
        }
        return best.values.sorted {
            if $0.from != $1.from { return $0.from < $1.from }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.to < $1.to
        }
    }
}
