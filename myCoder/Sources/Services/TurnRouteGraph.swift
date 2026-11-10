import Foundation

/// Provider-reported token usage for one routed role request.
struct ModelRoleUsage: Codable, Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?

    init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Actual result of one role request, including raw response evidence.
struct ModelRoleResult: Equatable, Sendable {
    var text: String
    var reasoning: String?
    var usage: ModelRoleUsage?
    var rawResponses: [String]?

    init(text: String, reasoning: String? = nil, usage: ModelRoleUsage? = nil, rawResponses: [String]? = nil) {
        self.text = text
        self.reasoning = reasoning
        self.usage = usage
        self.rawResponses = rawResponses
    }
}

/// One persisted node of the executed route graph.
struct TurnRouteJournalEntry: Codable, Equatable, Sendable {
    var id: String
    var sessionID: String?
    var role: ModelRole
    var assignment: ModelAssignment
    var startedAt: Date
    var finishedAt: Date?
    var inputArtifacts: [String]
    var result: String?
    var usage: ModelRoleUsage?
    var rawResponses: [String]?
    var error: String?

    /// Whether this node reached a real provider response.
    var isCompleted: Bool { error == nil && finishedAt != nil }
}

/// Terminal graph outcome after every node that actually ran.
enum TurnRouteOutcome: Equatable, Sendable {
    case completed
    case reviewLimitReached
    /// The graph stopped on a real error; `entries` still journal every node
    /// that ran, including the failed one.
    case failed
}

/// Report shown in the routing panel; it never claims an unexecuted node.
struct TurnRouteReport: Equatable, Sendable {
    var entries: [TurnRouteJournalEntry]
    var finalText: String?
    var outcome: TurnRouteOutcome

    /// Distinct providers really contacted during the turn.
    var usedProviderIDs: [String] {
        Array(Set(entries.map(\.assignment.providerID))).sorted()
    }
}

/// Full evidence of one graph run: the report (journal even on failure) and
/// the error that stopped it, if any. Exactly one of `error`/`finalText`
/// semantics applies: `error != nil` means the graph did not finish.
struct TurnRouteRunOutcome: Sendable {
    var report: TurnRouteReport
    var error: Error?
}

/// Conditional directed graph of role nodes for one send.
struct TurnRouteGraph: Equatable, Sendable {
    var initialRoles: [ModelRole]
    var maxReviewCycles: Int
    var requiresVisionFallback: Bool

    /// Builds the minimum honest chain for a mode and attachment shape.
    ///
    /// Вход: режим агента, наличие изображений, известную vision-capability
    /// основной модели, лимит циклов ревью.
    /// Выход: граф ролей.
    /// Зависимости: `AgentMode`, `ModelRole`.
    static func build(
        agentMode: AgentMode,
        hasImages: Bool = false,
        mainSupportsVision: Bool? = nil,
        maxReviewCycles: Int = 2
    ) -> TurnRouteGraph {
        let needsVision = hasImages && mainSupportsVision == false
        var roles: [ModelRole] = []
        if needsVision { roles.append(.vision) }
        switch agentMode {
        case .plan:
            roles.append(contentsOf: [.planning, .finalResponse])
        case .compose:
            roles.append(contentsOf: [.dispatch, .execution, .finalResponse])
        case .build:
            roles.append(contentsOf: [.dispatch, .planning, .research, .execution, .review, .finalResponse])
        }
        return TurnRouteGraph(
            initialRoles: roles,
            maxReviewCycles: maxReviewCycles,
            requiresVisionFallback: needsVision
        )
    }

    /// Short human-readable preview of the chain, without executing it.
    var chainPreview: String {
        initialRoles.map(\.displayName).joined(separator: " → ")
    }
}

/// Executes a route graph against an injected transport closure.
///
/// The runner has no network or UI dependency: every role request is delegated
/// to the caller, so tests prove ordering, limits, cancellation and honest
/// journaling independently from a particular provider transport.
struct TurnRouteRunner: Sendable {
    typealias Perform = @Sendable (ModelRole, ModelAssignment, String) async throws -> ModelRoleResult

    let configuration: ModelRoutingConfiguration
    let primary: ModelAssignment
    let graph: TurnRouteGraph
    let resolver: ModelRouteResolver

    /// Prepares a resolver from the same configuration and primary selection.
    init(configuration: ModelRoutingConfiguration, primary: ModelAssignment, graph: TurnRouteGraph) {
        self.configuration = configuration
        self.primary = primary
        self.graph = graph
        self.resolver = ModelRouteResolver(configuration: configuration, primary: primary)
    }

    /// Runs all initial nodes, bounded review corrections and returns evidence.
    ///
    /// Вход: id сессии, исходный пользовательский запрос, closure фактической
    /// отправки каждой роли.
    /// Выход: `TurnRouteReport` или брошенная ошибка/отмена; скрытый fallback
    /// запрещён.
    /// Зависимости: `runCollecting`.
    func run(sessionID: String?, request: String, perform: Perform) async throws -> TurnRouteReport {
        let outcome = await runCollecting(sessionID: sessionID, request: request, perform: perform)
        if let error = outcome.error { throw error }
        return outcome.report
    }

    /// Same execution as `run`, but the journal of every node that ran is
    /// returned even when the graph stopped on an error or cancellation —
    /// the routing panel must show the failed node with its real assignment
    /// instead of losing the evidence.
    ///
    /// Вход: те же, что у `run`.
    /// Выход: `TurnRouteRunOutcome` — журнал всегда, ошибка при провале.
    /// Зависимости: `ModelRouteResolver`, `ReviewResponseParser`.
    func runCollecting(sessionID: String?, request: String, perform: Perform) async -> TurnRouteRunOutcome {
        var entries: [TurnRouteJournalEntry] = []
        var artifacts: [ModelRole: String] = [:]

        do {
            for role in graph.initialRoles {
                if role == .review {
                    let reviewOutcome = try await runReviewCycle(
                        sessionID: sessionID,
                        request: request,
                        artifacts: &artifacts,
                        entries: &entries,
                        perform: perform
                    )
                    if reviewOutcome == .reviewLimitReached {
                        return TurnRouteRunOutcome(
                            report: TurnRouteReport(entries: entries, finalText: nil, outcome: .reviewLimitReached),
                            error: nil
                        )
                    }
                    continue
                }

                let result = try await execute(
                    role,
                    sessionID: sessionID,
                    request: request,
                    artifacts: artifacts,
                    entries: &entries,
                    perform: perform
                )
                artifacts[role] = result.text
                if role == .finalResponse {
                    return TurnRouteRunOutcome(
                        report: TurnRouteReport(entries: entries, finalText: result.text, outcome: .completed),
                        error: nil
                    )
                }
            }

            return TurnRouteRunOutcome(
                report: TurnRouteReport(
                    entries: entries,
                    finalText: artifacts[.finalResponse] ?? artifacts[.execution],
                    outcome: .completed
                ),
                error: nil
            )
        } catch {
            return TurnRouteRunOutcome(
                report: TurnRouteReport(entries: entries, finalText: nil, outcome: .failed),
                error: error
            )
        }
    }

    /// Runs one review; concrete findings trigger correction and re-review.
    ///
    /// Вход: общие артефакты графа, журнал, transport closure.
    /// Выход: `completed` или `reviewLimitReached`.
    /// Зависимости: `ReviewResponseParser`, `execute`.
    private func runReviewCycle(
        sessionID: String?,
        request: String,
        artifacts: inout [ModelRole: String],
        entries: inout [TurnRouteJournalEntry],
        perform: Perform
    ) async throws -> TurnRouteOutcome {
        var cycles = 0
        while true {
            try Task.checkCancellation()
            cycles += 1
            let reviewResult = try await execute(
                .review,
                sessionID: sessionID,
                request: request,
                artifacts: artifacts,
                entries: &entries,
                perform: perform
            )
            artifacts[.review] = reviewResult.text
            let issues = ReviewResponseParser.issues(from: reviewResult.text)
            if issues.isEmpty { return .completed }
            guard cycles < graph.maxReviewCycles else { return .reviewLimitReached }

            var correctionArtifacts = artifacts
            correctionArtifacts[.review] = ReviewResponseParser.findingsText(issues)
            let correction = try await execute(
                .correction,
                sessionID: sessionID,
                request: request,
                artifacts: correctionArtifacts,
                entries: &entries,
                perform: perform
            )
            artifacts[.correction] = correction.text
            artifacts[.execution] = correction.text
        }
    }

    /// Executes and journals a single role without any alternative provider.
    ///
    /// Вход: роль, id сессии, исходный запрос, накопленные артефакты, журнал,
    /// transport closure.
    /// Выход: реальный результат роли.
    /// Зависимости: `ModelRouteResolver`, `TurnRoutePrompts`.
    private func execute(
        _ role: ModelRole,
        sessionID: String?,
        request: String,
        artifacts: [ModelRole: String],
        entries: inout [TurnRouteJournalEntry],
        perform: Perform
    ) async throws -> ModelRoleResult {
        try Task.checkCancellation()
        let assignment = try resolver.validatedAssignment(for: role)
        let input = TurnRoutePrompts.input(
            role: role,
            request: request,
            artifacts: artifacts
        )
        var entry = TurnRouteJournalEntry(
            id: UUID().uuidString,
            sessionID: sessionID,
            role: role,
            assignment: assignment,
            startedAt: Date(),
            finishedAt: nil,
            inputArtifacts: Array(artifacts.keys.map(\.rawValue)).sorted(),
            result: nil,
            usage: nil,
            rawResponses: nil,
            error: nil
        )
        do {
            let result = try await perform(role, assignment, input)
            entry.finishedAt = Date()
            entry.result = result.text
            entry.usage = result.usage
            entry.rawResponses = result.rawResponses
            entries.append(entry)
            try Task.checkCancellation()
            return result
        } catch {
            entry.finishedAt = Date()
            entry.error = error.localizedDescription
            entries.append(entry)
            throw error
        }
    }
}

/// Minimal JSON contract for an independent review result.
enum ReviewResponseParser {
    private struct Payload: Decodable {
        let issues: [String]?
        let complete: Bool?
    }

    /// Extracts concrete issues; malformed output is never treated as clean.
    ///
    /// Вход: текст ответа ревью-модели.
    /// Выход: массив проблем; невалидный JSON даёт одну ошибку парсинга.
    /// Зависимости: `JSONDecoder`.
    static func issues(from text: String) -> [String] {
        guard let data = firstJSONObject(in: text)?.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? ["Review response is empty"] : ["Review response is not valid JSON: \(trimmed.prefix(200))"]
        }
        if let issues = payload.issues { return issues.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return payload.complete == true ? [] : ["Review did not confirm completion"]
    }

    /// Stable findings block sent to the correction role.
    static func findingsText(_ issues: [String]) -> String {
        issues.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for (offset, character) in text[start...].enumerated() {
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(start, offsetBy: offset)
                    return String(text[start...end])
                }
            }
        }
        return nil
    }
}

/// Builds factual prompts for every role from the user request and artifacts.
enum TurnRoutePrompts {
    /// Role-specific instruction plus prior results, with no invented evidence.
    ///
    /// Вход: роль, исходный запрос, артефакты предыдущих узлов.
    /// Выход: полный промпт роли.
    /// Зависимости: `ModelRole`.
    static func input(role: ModelRole, request: String, artifacts: [ModelRole: String]) -> String {
        var sections: [String] = [role.roleDescription, "User request:\n\(request)"]
        for dependency in dependencies(for: role) {
            if let artifact = artifacts[dependency]?.trimmingCharacters(in: .whitespacesAndNewlines), !artifact.isEmpty {
                sections.append("\(dependency.displayName) result:\n\(artifact)")
            }
        }
        sections.append(roleRule(role))
        return sections.joined(separator: "\n\n")
    }

    /// Fixed dependency order used when constructing each prompt.
    private static func dependencies(for role: ModelRole) -> [ModelRole] {
        switch role {
        case .dispatch, .vision: return []
        case .planning: return [.vision, .dispatch]
        case .research: return [.vision, .dispatch, .planning]
        case .execution: return [.vision, .planning, .research]
        case .review: return [.planning, .research, .execution]
        case .correction: return [.execution, .review]
        case .compaction: return []
        case .finalResponse: return [.vision, .planning, .research, .execution, .review, .correction]
        }
    }

    private static func roleRule(_ role: ModelRole) -> String {
        switch role {
        case .dispatch:
            return #"Return only JSON: {"branches":["code"|"text"|"web"|"image"],"needsPlan":true|false}"#
        case .planning:
            return "Return a concrete implementation plan with acceptance criteria. Do not modify files."
        case .research:
            return "Summarize only supplied evidence and missing information. Do not invent file contents."
        case .execution:
            return "Implement the requested work using the plan and evidence. Report only actions actually completed."
        case .review:
            return #"Return only JSON: {"issues":["specific problem"],"complete":true|false}"#
        case .correction:
            return "Fix every concrete review finding or explain exactly why a finding cannot be fixed."
        case .compaction:
            return "Produce a factual compact summary suitable for the next model."
        case .vision:
            return "Describe visible text, UI elements and layout exactly as observed. Do not guess hidden content."
        case .finalResponse:
            return "Combine actual completed work into the final answer. Never claim unexecuted changes."
        }
    }
}

/// Durable routing evidence per chat, kept outside credentials and model output.
struct ModelRouteJournalStore {
    private let defaults: UserDefaults
    private let key = "com.mycoder.modelRouteJournal"
    private let maxEntriesPerSession = 50

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Appends one executed node to the selected chat's journal.
    func append(_ entry: TurnRouteJournalEntry) {
        guard let sessionID = entry.sessionID, !sessionID.isEmpty else { return }
        var map = loadAll()
        var entries = map[sessionID] ?? []
        entries.append(entry)
        if entries.count > maxEntriesPerSession {
            entries.removeFirst(entries.count - maxEntriesPerSession)
        }
        map[sessionID] = entries
        save(map)
    }

    /// Returns the persisted graph evidence for one chat.
    func entries(sessionID: String?) -> [TurnRouteJournalEntry] {
        guard let sessionID, !sessionID.isEmpty else { return [] }
        return loadAll()[sessionID] ?? []
    }

    /// Removes routing evidence when a chat is deleted.
    func clear(sessionID: String) {
        var map = loadAll()
        map.removeValue(forKey: sessionID)
        save(map)
    }

    private func loadAll() -> [String: [TurnRouteJournalEntry]] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: [TurnRouteJournalEntry]].self, from: data)) ?? [:]
    }

    private func save(_ map: [String: [TurnRouteJournalEntry]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
