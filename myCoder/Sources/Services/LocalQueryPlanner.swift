import Foundation
import os

/// What a local model may add to the deterministic query plan.
///
/// The plan is a *pointer list*: terms to rank with, symbols and files that
/// really exist in the project, and memory tags worth looking at. It never
/// carries code or line numbers — the host owns retrieval and citations, so a
/// model that invents a line range can only be ignored, never obeyed.
struct LocalQueryPlan: Equatable, Sendable {
    let intent: LocalQueryIntent
    let terms: [String]
    let symbols: [String]
    let files: [String]
    let memoryTags: [String]

    var isEmpty: Bool {
        terms.isEmpty && symbols.isEmpty && files.isEmpty && memoryTags.isEmpty
    }
}

/// A fixed vocabulary keeps the intent field comparable between models; an
/// unknown word becomes `.other` instead of leaking into the pack.
enum LocalQueryIntent: String, CaseIterable, Equatable, Sendable {
    case fix
    case add
    case explain
    case test
    case refactor
    case other

    static func normalized(_ raw: String) -> LocalQueryIntent {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return LocalQueryIntent(rawValue: value) ?? .other
    }
}

/// One project entity the planner is allowed to name. Only the path, the kind
/// and the name travel to the model — never a body or a line range.
struct LocalPlannerEntity: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case file
        case symbol
    }

    let kind: Kind
    let path: String
    let name: String
}

/// The bounded slice of the project the planner sees: top-K files, a few
/// symbols each, and the memory tags that already exist.
struct LocalPlannerContext: Equatable, Sendable {
    let entities: [LocalPlannerEntity]
    let memoryTags: [String]

    var files: [String] {
        var result: [String] = []
        var seen = Set<String>()
        for entity in entities where entity.kind == .file {
            guard seen.insert(entity.path).inserted else { continue }
            result.append(entity.path)
        }
        return result
    }

    var symbolNames: [String] {
        var result: [String] = []
        var seen = Set<String>()
        for entity in entities where entity.kind == .symbol {
            guard seen.insert(entity.name).inserted else { continue }
            result.append(entity.name)
        }
        return result
    }

    var knownPaths: Set<String> {
        Set(entities.filter { $0.kind == .file }.map(\.path))
    }

    /// Symbol name → canonical spelling, so a case-insensitive match still
    /// yields the identifier exactly as it appears in source.
    var symbolLookup: [String: String] {
        var result: [String: String] = [:]
        for entity in entities where entity.kind == .symbol {
            let key = entity.name.lowercased()
            if result[key] == nil { result[key] = entity.name }
        }
        return result
    }
}

/// Builds the bounded planner context. Selection is the same deterministic
/// ranking the compiler uses, so the planner is steered to the files the
/// message already points at — not handed the whole project.
enum LocalPlannerContextBuilder {

    static let maxFiles = 8
    static let maxSymbolsPerFile = 4
    static let maxMemoryTags = 8

    static func build(message: String,
                      board: ContextBoard,
                      memories: [ProjectMemoryChunk],
                      maxFiles: Int = maxFiles) -> LocalPlannerContext {
        let plan = ContextQueryPlanner.plan(for: message)
        let query = (plan.terms + plan.symbols).joined(separator: " ")
        let candidates = CandidateRanker.rank(
            board: board,
            query: query,
            limit: max(1, maxFiles),
            budgetBytes: Int.max
        )

        var entities: [LocalPlannerEntity] = []
        var seenSymbols = Set<String>()
        for candidate in candidates {
            entities.append(LocalPlannerEntity(
                kind: .file,
                path: candidate.path,
                name: (candidate.path as NSString).lastPathComponent
            ))
            for symbol in candidate.matchedSymbols.prefix(maxSymbolsPerFile) {
                let key = "\(candidate.path)|\(symbol.name)"
                guard seenSymbols.insert(key).inserted else { continue }
                entities.append(LocalPlannerEntity(
                    kind: .symbol,
                    path: candidate.path,
                    name: symbol.name
                ))
            }
        }

        var tags: [String] = []
        var seenTags = Set<String>()
        for chunk in memories {
            for tag in chunk.tags where !tag.isEmpty {
                guard seenTags.insert(tag).inserted else { continue }
                tags.append(tag)
                if tags.count >= maxMemoryTags { break }
            }
            if tags.count >= maxMemoryTags { break }
        }

        return LocalPlannerContext(entities: entities, memoryTags: tags)
    }
}

/// The prompt is the only place where project data leaves the host for the
/// planner, so it is built from the bounded context and nothing else.
enum LocalPlannerPromptBuilder {

    static let system = """
    You help a code assistant find context. You never write code.
    Answer with ONE JSON object and nothing else:
    {"intent": "fix|add|explain|test|refactor|other",
     "terms": ["ranking words"],
     "symbols": ["exact symbol names from the list"],
     "files": ["exact file paths from the list"],
     "memory_tags": ["tags from the list"]}
    Rules: use only entities from the lists below; never invent a path or a
    name; never include code, line numbers, or explanations.
    """

    static func build(message: String, context: LocalPlannerContext) -> (system: String, user: String) {
        var lines: [String] = []
        lines.append("User request:")
        lines.append(message)
        lines.append("")
        lines.append("Files (path):")
        if context.files.isEmpty {
            lines.append("- none")
        } else {
            for path in context.files { lines.append("- \(path)") }
        }
        lines.append("")
        lines.append("Symbols (path → name):")
        let symbols = context.entities.filter { $0.kind == .symbol }
        if symbols.isEmpty {
            lines.append("- none")
        } else {
            for symbol in symbols { lines.append("- \(symbol.path) → \(symbol.name)") }
        }
        lines.append("")
        lines.append("Memory tags:")
        if context.memoryTags.isEmpty {
            lines.append("- none")
        } else {
            lines.append("- " + context.memoryTags.joined(separator: ", "))
        }
        return (system, lines.joined(separator: "\n"))
    }
}

/// Why a plan was rejected. Every case ends in fallback, never in a partially
/// applied plan: a half-trusted answer is worse than the deterministic one.
enum LocalQueryPlanError: Error, Equatable, LocalizedError {
    case notJSON
    case notAnObject
    case tooManyItems(field: String)
    case valueTooLong(field: String)
    case codeDetected(field: String)
    case lineNumberDetected(field: String)
    case wrongType(field: String)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "no JSON object in the answer"
        case .notAnObject: return "the answer is not a JSON object"
        case .tooManyItems(let field): return "too many items in \(field)"
        case .valueTooLong(let field): return "a value in \(field) is too long"
        case .codeDetected(let field): return "code found in \(field)"
        case .lineNumberDetected(let field): return "line number found in \(field)"
        case .wrongType(let field): return "wrong type in \(field)"
        }
    }
}

/// Parses and validates the planner answer.
///
/// Validation is the safety boundary: a plan that contains a code snippet or a
/// `file:line` reference is rejected as a whole, because accepting the rest
/// would make the host act on an answer that did not follow the contract.
enum LocalQueryPlanParser {

    static let maxItemsPerField = 20
    static let maxValueLength = 80

    private static let lineReference = try? NSRegularExpression(pattern: #":\d{1,6}\b"#)
    /// Characters that do not belong in a name, a term or a tag.
    private static let codeCharacters: Set<Character> = [
        "{", "}", "(", ")", ";", "=", "<", ">", "*", "`", "\\", "\"", "'"
    ]

    static func parse(_ raw: String) throws -> LocalQueryPlan {
        guard let json = extractJSONObject(from: raw) else {
            throw LocalQueryPlanError.notJSON
        }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalQueryPlanError.notAnObject
        }

        let intent = LocalQueryIntent.normalized(string(object["intent"]) ?? "")
        let terms = try strings(object, keys: ["terms"], field: "terms")
        let symbols = try strings(object, keys: ["symbols"], field: "symbols")
        let files = try strings(object, keys: ["files"], field: "files")
        let tags = try strings(object, keys: ["memory_tags", "memoryTags"], field: "memory_tags")

        return LocalQueryPlan(
            intent: intent,
            terms: dedupe(terms.map { $0.lowercased() }),
            symbols: dedupe(symbols),
            files: dedupe(files),
            memoryTags: dedupe(tags.map { $0.lowercased() })
        )
    }

    /// Keeps only entities that really exist in the bounded context. Unknown
    /// ones are recorded and logged — never an error, because a model naming a
    /// file it cannot see is a normal miss, not a broken turn.
    static func resolve(_ plan: LocalQueryPlan,
                        context: LocalPlannerContext) -> (plan: LocalQueryPlan, dropped: [String]) {
        var dropped: [String] = []

        let knownPaths = context.knownPaths
        let files = plan.files.compactMap { requested -> String? in
            if knownPaths.contains(requested) { return requested }
            let match = knownPaths.first { $0.lowercased() == requested.lowercased() }
            if let match { return match }
            dropped.append("file:\(requested)")
            return nil
        }

        let lookup = context.symbolLookup
        let symbols = plan.symbols.compactMap { requested -> String? in
            if let canonical = lookup[requested.lowercased()] { return canonical }
            dropped.append("symbol:\(requested)")
            return nil
        }

        let knownTags = Set(context.memoryTags.map { $0.lowercased() })
        let tags = plan.memoryTags.compactMap { tag -> String? in
            if knownTags.contains(tag.lowercased()) { return tag.lowercased() }
            dropped.append("tag:\(tag)")
            return nil
        }

        let resolved = LocalQueryPlan(
            intent: plan.intent,
            terms: plan.terms,
            symbols: symbols,
            files: files,
            memoryTags: tags
        )
        for miss in dropped {
            logger.debug("planner dropped unknown entity: \(miss, privacy: .public)")
        }
        return (resolved, dropped)
    }

    private static let logger = Logger(
        subsystem: "com.mycoder",
        category: "LocalQueryPlanner"
    )

    // MARK: - Parsing helpers

    /// Models like to wrap JSON in a fenced block or add a sentence before it.
    /// The first `{` and the matching last `}` are the object to parse.
    static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        return String(raw[start...end])
    }

    private static func strings(_ object: [String: Any],
                                keys: [String],
                                field: String) throws -> [String] {
        guard let raw = keys.compactMap({ object[$0] }).first else { return [] }
        // A model may answer a single item without an array; accept it as one.
        let items: [Any]
        if let list = raw as? [Any] {
            items = list
        } else if raw is String {
            items = [raw]
        } else {
            throw LocalQueryPlanError.wrongType(field: field)
        }
        guard items.count <= maxItemsPerField else {
            throw LocalQueryPlanError.tooManyItems(field: field)
        }
        var result: [String] = []
        for item in items {
            guard let value = item as? String else {
                throw LocalQueryPlanError.wrongType(field: field)
            }
            try validate(value, field: field)
            result.append(value)
        }
        return result
    }

    private static func validate(_ value: String, field: String) throws {
        if value.count > maxValueLength {
            throw LocalQueryPlanError.valueTooLong(field: field)
        }
        if value.contains("\n") || value.contains("\r") {
            throw LocalQueryPlanError.codeDetected(field: field)
        }
        if value.contains(where: { codeCharacters.contains($0) }) {
            throw LocalQueryPlanError.codeDetected(field: field)
        }
        let range = NSRange(location: 0, length: (value as NSString).length)
        if lineReference?.firstMatch(in: value, options: [], range: range) != nil {
            throw LocalQueryPlanError.lineNumberDetected(field: field)
        }
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in values {
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count >= maxItemsPerField { break }
        }
        return result
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}

/// How the plan for this turn was produced. The UI shows the fallback reason,
/// so a degraded turn never looks like a model-driven one.
enum LocalQueryPlanStatus: Equatable, Sendable {
    case local(model: String)
    case fallback(reason: String)
}

struct LocalQueryPlanResult: Equatable, Sendable {
    /// nil means the deterministic plan stands unchanged.
    let plan: LocalQueryPlan?
    let status: LocalQueryPlanStatus
    /// Entities the model named that the bounded context does not contain.
    let dropped: [String]
}

enum LocalQueryPlannerError: LocalizedError, Equatable {
    case timedOut
    case noLocalModel
    case noEntities

    var errorDescription: String? {
        switch self {
        case .timedOut: return "timeout"
        case .noLocalModel: return "no local model"
        case .noEntities: return "no entities to plan with"
        }
    }
}

/// Optional local planner. It runs one non-streaming turn against the user's
/// own local model, inside a hard timeout, and returns either a validated plan
/// or a fallback status. It can never block or break the send.
struct LocalQueryPlanner {

    static let defaultTimeout: TimeInterval = 8

    let runner: LocalModelRunner
    let timeout: TimeInterval

    init(runner: LocalModelRunner, timeout: TimeInterval = defaultTimeout) {
        self.runner = runner
        self.timeout = timeout
    }

    func plan(message: String, context: LocalPlannerContext) async -> LocalQueryPlanResult {
        guard !context.entities.isEmpty else {
            return Self.fallback(.noEntities)
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.fallback(.noEntities) }

        let prompt = LocalPlannerPromptBuilder.build(message: trimmed, context: context)
        let outcome: LocalModelRunner.Outcome
        do {
            outcome = try await withTimeout { [runner] in
                try await runner.run(prompt: prompt.user, system: prompt.system)
            }
        } catch {
            let reason = (error as? LocalQueryPlannerError) == .timedOut
                ? LocalQueryPlannerError.timedOut.localizedDescription
                : error.localizedDescription
            Logger(subsystem: "com.mycoder", category: "LocalQueryPlanner")
                .debug("planner fallback: \(reason, privacy: .public)")
            return Self.fallback(reason)
        }

        let parsed: LocalQueryPlan
        do {
            parsed = try LocalQueryPlanParser.parse(outcome.text)
        } catch {
            let reason = error.localizedDescription
            Logger(subsystem: "com.mycoder", category: "LocalQueryPlanner")
                .debug("planner answer rejected: \(reason, privacy: .public)")
            return Self.fallback(reason)
        }

        let resolved = LocalQueryPlanParser.resolve(parsed, context: context)
        guard !resolved.plan.isEmpty else { return Self.fallback("empty plan") }
        return LocalQueryPlanResult(
            plan: resolved.plan,
            status: .local(model: outcome.candidate.model),
            dropped: resolved.dropped
        )
    }

    private static func fallback(_ error: LocalQueryPlannerError) -> LocalQueryPlanResult {
        LocalQueryPlanResult(plan: nil, status: .fallback(reason: error.localizedDescription), dropped: [])
    }

    private static func fallback(_ reason: String) -> LocalQueryPlanResult {
        LocalQueryPlanResult(plan: nil, status: .fallback(reason: reason), dropped: [])
    }

    /// Races the model against a sleep; whichever finishes first wins and the
    /// loser is cancelled. A hung local server therefore costs at most
    /// `timeout` seconds and the deterministic plan takes over.
    private func withTimeout<T>(_ work: @escaping () async throws -> T) async throws -> T {
        let seconds = max(0.001, timeout)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LocalQueryPlannerError.timedOut
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw LocalQueryPlannerError.timedOut
            }
            return value
        }
    }
}

/// Storage key and default for the planner switch. Off by default: a local
/// model may be slow or absent, so the feature is opt-in.
enum LocalPlannerSettings {
    static let storageKey = "com.mycoder.localQueryPlannerEnabled"
    static let defaultEnabled = false

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultEnabled
    }
}
