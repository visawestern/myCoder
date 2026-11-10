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
    /// Questions for the main model to investigate; these are hypotheses,
    /// never statements that a dependency exists or may be deleted.
    let questions: [String]
    /// Installed skill ids selected from the visible catalog only.
    let skills: [String]
    /// Task-specific guidance on HOW to work: a bounded procedure selected
    /// by the internal model, subordinate to the user and project rules.
    let instructions: [String]

    init(intent: LocalQueryIntent, terms: [String], symbols: [String], files: [String],
         memoryTags: [String], questions: [String] = [], skills: [String] = [],
         instructions: [String] = []) {
        self.intent = intent
        self.terms = terms
        self.symbols = symbols
        self.files = files
        self.memoryTags = memoryTags
        self.questions = questions
        self.skills = skills
        self.instructions = instructions
    }

    var isEmpty: Bool {
        terms.isEmpty && symbols.isEmpty && files.isEmpty && memoryTags.isEmpty
            && questions.isEmpty && skills.isEmpty && instructions.isEmpty
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
    /// Bounded at prompt construction: recent dialog, relevant memory text,
    /// and project rules supplied by the turn owner.
    let taskContext: String
    let graphContext: String
    let skillIDs: [String]

    init(entities: [LocalPlannerEntity], memoryTags: [String],
         taskContext: String = "", graphContext: String = "", skillIDs: [String] = []) {
        self.entities = entities
        self.memoryTags = memoryTags
        self.taskContext = taskContext
        self.graphContext = graphContext
        self.skillIDs = Array(Set(skillIDs.filter {
            !$0.isEmpty && $0.count <= 80 && !$0.contains("\n") && !$0.contains("\r")
        })).sorted().prefix(LocalPlannerPromptBuilder.maxSkillCatalogItems).map { $0 }
    }

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

/// Builds the bounded planner context. Lexical matches use the compiler's
/// top-K ranking. Without matches, a stable directory of up to 64 real files
/// lets the internal model discover semantic links across request languages.
/// The prompt states the directory limit; it never claims full graph coverage.
enum LocalPlannerContextBuilder {

    static let maxFiles = 8
    static let maxSymbolsPerFile = 4
    static let maxMemoryTags = 8
    /// A semantic planner needs real names even when the request's language
    /// has no lexical overlap with the source. This is a directory, not code.
    static let maxDiscoveryFiles = 64

    static func build(message: String,
                      board: ContextBoard,
                      memories: [ProjectMemoryChunk],
                      maxFiles: Int = maxFiles,
                      taskContext: String = "",
                      graphContext: String = "",
                      skillIDs: [String] = []) -> LocalPlannerContext {
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
        func append(path: String, symbols: [SymbolDeclaration]) {
            entities.append(LocalPlannerEntity(
                kind: .file, path: path, name: (path as NSString).lastPathComponent
            ))
            for symbol in symbols.prefix(maxSymbolsPerFile) {
                let key = "\(path)|\(symbol.name)"
                guard seenSymbols.insert(key).inserted else { continue }
                entities.append(LocalPlannerEntity(kind: .symbol, path: path, name: symbol.name))
            }
        }
        var discoveryNote = ""
        if candidates.isEmpty {
            let eligible = board.entries.filter {
                !ProjectFileIndexLogic.isSecretFile(relativePath: $0.path)
                    && $0.language.caseInsensitiveCompare("binary") != .orderedSame
                    && $0.size <= CandidateRanker.maxCandidateFileBytes
            }.sorted { $0.path < $1.path }
            let visible = Array(eligible.prefix(maxDiscoveryFiles))
            for entry in visible { append(path: entry.path, symbols: entry.symbols) }
            if !eligible.isEmpty {
                discoveryNote = "Семантический обзор: точных совпадений запроса нет; каталог показывает \(visible.count) из \(eligible.count) файлов. Отсутствие файла в этом ограниченном каталоге не доказывает отсутствие зависимости."
            }
        } else {
            for candidate in candidates {
                // A filename match is useful even if none of its symbols
                // matched a query token: show its real declarations too.
                let symbols = candidate.matchedSymbols.isEmpty
                    ? board.entries.first(where: { $0.path == candidate.path })?.symbols ?? []
                    : candidate.matchedSymbols
                append(path: candidate.path, symbols: symbols)
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

        return LocalPlannerContext(entities: entities, memoryTags: tags,
                                   taskContext: [discoveryNote, taskContext].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                                   graphContext: graphContext,
                                   skillIDs: skillIDs)
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

/// Storage key and default for the planner switch. On by default (user
/// directive 2026-11-03): the internal model is the component that turns the
/// request into a plan for context assembly, and an opt-in switch meant it
/// never ran. A slow or absent model degrades to a visible fallback, which is
/// honest — silently skipping the planner is not.
enum LocalPlannerSettings {
    static let storageKey = "com.mycoder.localQueryPlannerEnabled"
    static let defaultEnabled = true

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultEnabled
    }
}
