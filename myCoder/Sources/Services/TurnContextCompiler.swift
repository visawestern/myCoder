import Foundation

/// What the turn compiler understood from the user's message. Built from the
/// text alone — no model, no network, same answer every time.
struct ContextQueryPlan: Equatable, Sendable {
    /// Lowercase terms used for ranking.
    let terms: [String]
    /// Identifiers that look like code (`UserStore`, `testLoad`).
    let symbols: [String]
    /// Explicit project-relative paths in the message.
    let files: [String]
    /// Line numbers the user pointed at (`File.swift:42`).
    let lineNumbers: [Int]
}

enum ContextQueryPlanner {

    static func plan(for message: String) -> ContextQueryPlan {
        let files = paths(in: message)
        let lineNumbers = lineNumbers(in: message)
        let symbols = symbols(in: message)
        var terms = CandidateRanker.queryTerms(message)
        for symbol in symbols {
            let lower = symbol.lowercased()
            if !terms.contains(lower) { terms.append(lower) }
        }
        return ContextQueryPlan(terms: terms, symbols: symbols, files: files, lineNumbers: lineNumbers)
    }

    private static func paths(in text: String) -> [String] {
        let pattern = #"([A-Za-z0-9_./\-]+\.[A-Za-z0-9]{1,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              !text.contains("\n#") // cheap guard against huge inputs
        else { return [] }
        let ns = text as NSString
        var result: [String] = []
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range(at: 1))
            // A path must contain a separator or start with a known source
            // prefix; `UserStore.swift` and `testLoad()` are different things.
            if !result.contains(value) { result.append(value) }
        }
        return result
    }

    private static func lineNumbers(in text: String) -> [Int] {
        let pattern = #":(\d{1,6})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var result: [Int] = []
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard let value = Int(ns.substring(with: match.range(at: 1))), !result.contains(value) else { continue }
            result.append(value)
        }
        return result
    }

    private static func symbols(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            guard current.count >= 3 else { current = ""; return }
            let looksLikeCode = current.contains(where: { $0.isUppercase })
                || current.contains("_")
                || current.first?.isLowercase == true && current.dropFirst().contains(where: { $0.isUppercase })
            if looksLikeCode, !result.contains(current) { result.append(current) }
            current = ""
        }
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}

// MARK: - Pack

struct ContextCitation: Equatable, Sendable {
    let path: String
    let startLine: Int
    let endLine: Int
    let symbol: String?
}

struct ContextSection: Equatable, Sendable {
    let title: String
    let body: String
}

struct DroppedSource: Equatable, Sendable {
    let path: String
    let reason: String
}

struct ContextManifest: Equatable, Sendable {
    /// Paths that really made it into the pack, in order.
    let included: [String]
    /// Paths that were considered and left out, with the reason.
    let dropped: [DroppedSource]
    /// How many files were ranked before the budget was applied.
    let considered: Int
}

struct CompiledContextPack: Equatable, Sendable {
    let sections: [ContextSection]
    let citations: [ContextCitation]
    let unknowns: [String]
    let manifest: ContextManifest
    let estimatedTokens: Int
    let text: String
    /// Ids of the stored project memories that made it into the pack.
    let memoryIDs: [String]
    /// The task state that replaced the raw transcript, when one was built.
    let ledgerSummary: String?
    /// How the query plan was produced, when the optional local planner ran.
    /// `.fallback` stays visible in the pack instead of being hidden.
    let planStatus: LocalQueryPlanStatus?
    /// The system instruction sent alongside this pack. Kept so the context
    /// viewer can show the whole payload, not only the evidence half.
    let systemPrompt: String?

    /// The complete payload in assembly order: system instruction, then point
    /// context, then the user's request. `text` is only the wire half.
    var auditText: String {
        guard let systemPrompt, !systemPrompt.isEmpty else { return text }
        return "## Системная инструкция\n\(systemPrompt)\n\n\(text)"
    }
}

/// Assembles the context for one user message: plan → candidates → real code
/// blocks → budget → pack. Deterministic by construction (no model, no dates).
enum TurnContextCompiler {

    /// File-read budget for one context pack, in tokens. Raised to 128k per
    /// the user directive (2026-11-08) so a real codebase's relevant files
    /// fit; 6k dropped most candidates on a project with many hits.
    static let defaultBudgetTokens = 128_000
    /// How many ranked files may enter the pack before the budget applies.
    static let defaultMaxFiles = 8
    /// Rough but stable: four bytes per token. Only used for budgeting, never
    /// shown as a billing number.
    static let bytesPerToken = 4

    static func compile(message: String,
                        board: ContextBoard,
                        projectRoot: String,
                        memories: [ProjectMemoryChunk] = [],
                        ledger: TaskLedger? = nil,
                        chatHistory: [ChatHistoryBuilder.Turn] = [],
                        budgetTokens: Int = defaultBudgetTokens,
                        maxFiles: Int = defaultMaxFiles,
                        localPlan: LocalQueryPlanResult? = nil,
                        systemPrompt: String? = nil,
                        skillsDirectory: URL? = nil,
                        records: [FileIndexRecord]? = nil,
                        impact: ImpactReport? = nil,
                        lspSection: ContextSection? = nil,
                        onStage: (@Sendable (ContextStageLogLogic.Stage) -> Void)? = nil) -> CompiledContextPack {
        let deterministic = ContextQueryPlanner.plan(for: message)
        let plan = merged(deterministic, with: localPlan?.plan)
        let query = (plan.terms + plan.symbols + plan.files).joined(separator: " ")
        var candidates = CandidateRanker.rank(
            board: board,
            query: query,
            limit: max(1, maxFiles),
            budgetBytes: Int.max
        )
        // Explicit/validated file selections must survive lexical ranking.
        for path in plan.files.reversed() {
            guard let entry = board.entries.first(where: { $0.path == path }) else { continue }
            candidates.removeAll { $0.path == path }
            candidates.insert(ContextCandidate(path: path, language: entry.language, score: 1000,
                                               lastModified: entry.lastModified, estimatedBytes: entry.size,
                                               matchedSymbols: entry.symbols.filter { plan.symbols.contains($0.name) }), at: 0)
        }
        // Один файл — один кандидат. Доска может прийти с повторами путей
        // (несколько источников), и без этого файл занимал два слота.
        var seenCandidatePaths = Set<String>()
        candidates = candidates.filter { seenCandidatePaths.insert($0.path).inserted }
        candidates = Array(candidates.prefix(max(1, maxFiles)))
        // A path the user typed explicitly always comes first.
        let explicit = Set(plan.files)
        if !explicit.isEmpty {
            candidates.sort {
                let left = explicit.contains($0.path) ? 1 : 0
                let right = explicit.contains($1.path) ? 1 : 0
                if left != right { return left > right }
                return $0.score > $1.score
            }
        }

        let budgetBytes = max(0, budgetTokens * bytesPerToken)
        // The request is never shortened: the model must see every word the
        // user typed. The budget applies to the evidence around it.
        let request = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [ContextSection] = [
            ContextSection(title: "Запрос", body: request)
        ]
        // The plan that steered retrieval is stated in one line. On fallback
        // the reason is shown instead of silently pretending the local model
        // planned the turn.
        if let localPlan {
            sections.append(ContextSection(
                title: "План запроса",
                body: planTraceText(localPlan)
            ))
        }
        // The chat itself is context: prior turns are part of what the model
        // needs for a coherent next step (user directive 2026-10-30 — later
        // prompts in a chat use the studied data AND the chat history).
        if !chatHistory.isEmpty {
            sections.append(historySection(chatHistory))
        }
        var citations: [ContextCitation] = []
        var unknowns: [String] = []
        var included: [String] = []
        var dropped: [DroppedSource] = []
        // Файлы, которые НЕ удалось прочитать (путь + причина) — секция «Чтение файлов».
        var readFailures: [DroppedSource] = []

        // Task state comes before evidence: the model must know what is being
        // built and what was already decided before reading code.
        let ledgerSummary = ledger?.summaryText
        if let ledgerSummary, !ledgerSummary.isEmpty {
            sections.append(ContextSection(title: "Состояние задачи", body: ledgerSummary))
        }

        // Durable facts the user wrote with /remember. They are ranked against
        // the same query as the code, and each line keeps its source, so a
        // stale memory can be traced back and removed. Tags the planner
        // recognised widen the memory query without inventing facts.
        var memoryQuery = message
        if let tags = localPlan?.plan?.memoryTags, !tags.isEmpty {
            memoryQuery += " " + tags.joined(separator: " ")
        }
        // Одинаковые факты памяти не должны повторяться в пакете.
        var seenMemoryTexts = Set<String>()
        let relevantMemories = ProjectMemoryRanker.rank(memories, query: memoryQuery, limit: 5)
            .filter { seenMemoryTexts.insert(ContextDeduplication.normalize($0.text)).inserted }
        let memoryIDs = relevantMemories.map(\.id)
        if !relevantMemories.isEmpty {
            let lines = relevantMemories.map { chunk -> String in
                let source: String
                if let messageID = chunk.sourceMessageID, !messageID.isEmpty {
                    source = "сообщение \(messageID)"
                } else {
                    source = "id \(chunk.id)"
                }
                return "- [\(chunk.kind)] \(chunk.text) (источник: \(source))"
            }
            sections.append(ContextSection(title: "Память проекта", body: lines.joined(separator: "\n")))
        }

        // The project's own rules and the skill matching this request. Both
        // are read from disk and filtered by the user's words, so an unrelated
        // skill or a missing AGENTS.md adds nothing.
        onStage?(.skills)
        let evidenceQuery = ([message] + plan.symbols + plan.terms).joined(separator: " ")
        if let rules = TurnEvidence.projectInstructions(projectPath: projectRoot) { sections.append(rules) }
        let skillSections: [ContextSection]
        if let selected = localPlan?.plan?.skills {
            skillSections = TurnEvidence.selectedSkills(ids: selected, directory: skillsDirectory)
        } else {
            skillSections = TurnEvidence.matchingSkills(query: evidenceQuery, skillsDirectory: skillsDirectory)
        }
        sections.append(contentsOf: skillSections)
        if let questions = localPlan?.plan?.questions, !questions.isEmpty {
            sections.append(ContextSection(title: "Вопросы внутренней модели", body:
                "Гипотезы для проверки по коду, не готовые выводы:\n" + questions.map { "- " + $0 }.joined(separator: "\n")))
        }
        // Owner design 2026-11-04: every task turn carries "how to work"
        // instructions picked by the prompt. The internal model's own
        // instructions win; when the planner fell back (no model assigned /
        // no answer) the deterministic catalog keeps the floor — marked by
        // source so the viewer stays honest about who picked them.
        let modelInstructions = localPlan?.plan?.instructions ?? []
        let instructions: [String]
        let instructionSource: String
        if !modelInstructions.isEmpty {
            instructions = modelInstructions
            instructionSource = "внутренней модели"
        } else {
            let catalogIntent = localPlan?.plan?.intent ?? TaskInstructionCatalog.intent(for: message)
            instructions = TaskInstructionCatalog.instructions(for: catalogIntent, message: message)
            instructionSource = "каталог задач"
        }
        if !instructions.isEmpty {
            sections.append(ContextSection(title: "Инструкции задачи", body:
                "Рекомендации (\(instructionSource)) по выполнению текущего запроса. Они не отменяют запрос пользователя и правила проекта; проверяй применимость по коду.\n"
                + instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")))
        }
        // Real graph evidence: symbols plus their edges. The flat board knows
        // names but no relations, so this is the only place a caller sees what
        // calls what. A failure degrades to a stated gap, never a crash.
        if let records, !records.isEmpty {
            onStage?(.graph)
            do {
                let graph = try TurnEvidence.graph(
                    projectPath: projectRoot,
                    query: query,
                    records: records
                )
                if !graph.body.isEmpty {
                    sections.append(graph)
                }
            } catch {
                unknowns.append("граф кода недоступен: \(error.localizedDescription)")
            }
        }

        // Harness questions about dependencies (user directive 2026-11-03):
        // a structural change is not one function — the model must walk every
        // reverse edge and decide its fate. The section is only present when
        // the analyzer really found edges; an empty report never renders.
        if let impact {
            onStage?(.impact)
            if !impact.isEmpty { sections.append(impact.section()) }
        }

        if candidates.isEmpty {
            unknowns.append("в индексе проекта нет файлов, подходящих под запрос")
        }

        onStage?(.files)
        for candidate in candidates {
            guard let ref = reference(for: candidate, plan: plan) else {
                dropped.append(DroppedSource(path: candidate.path, reason: "не найден подходящий символ"))
                continue
            }
            let block: String
            do {
                block = try ContextMaterializer.block(for: ref, projectRoot: projectRoot)
            } catch {
                // Точная ссылка не сработала — не теряем файл: показываем его
                // целиком с пометкой причины (запрос 2026-11-13). Успешный
                // fallback — НЕ пробел: файл ушёл в контекст.
                let detail = (error as? LocalCompilerError)?.errorDescription ?? error.localizedDescription
                if let fallback = fallbackBlock(
                    path: candidate.path,
                    projectRoot: projectRoot,
                    reason: "точная ссылка не сработала: \(detail) — показан весь файл"
                ) {
                    block = fallback
                } else {
                    readFailures.append(DroppedSource(path: candidate.path, reason: detail))
                    dropped.append(DroppedSource(path: candidate.path, reason: "файл не прочитан"))
                    continue
                }
            }

            let section = ContextSection(title: candidate.path, body: "````\n" + block + "\n````")
            let proposed = sections + [section]
            if render(sections: proposed, unknowns: unknowns, dropped: dropped).utf8.count > budgetBytes {
                dropped.append(DroppedSource(
                    path: candidate.path,
                    reason: "не влезает в бюджет \(budgetTokens) токенов"
                ))
                continue
            }
            sections.append(section)
            if let citation = citation(for: ref, block: block) {
                citations.append(citation)
            }
            included.append(candidate.path)
        }

        // Dependents' code is evidence too: the model must see the caller it
        // is deciding about with real lines, not only its name in the graph.
        // Same budget and same honesty rules as the primary candidates.
        if let impact, !impact.isEmpty {
            for ref in impact.refs {
                guard !citations.contains(where: { citation in
                    citation.path == ref.path && ((ref.symbol != nil && citation.symbol == ref.symbol)
                        || (ref.startLine.map { citation.startLine <= $0 } == true
                            && ref.endLine.map { citation.endLine >= $0 } == true))
                }) else { continue }
                let block: String
                do {
                    block = try ContextMaterializer.block(for: ref, projectRoot: projectRoot)
                } catch {
                    // Зависимость не читается по точной ссылке — весь файл с
                    // пометкой; успешный fallback не создаёт пробел.
                    let detail = error.localizedDescription
                    if let fallback = fallbackBlock(
                        path: ref.path,
                        projectRoot: projectRoot,
                        reason: "точная ссылка не сработала: \(detail) — показан весь файл"
                    ) {
                        block = fallback
                    } else {
                        readFailures.append(DroppedSource(path: ref.path, reason: detail))
                        dropped.append(DroppedSource(path: ref.path, reason: "зависимость не прочитана"))
                        continue
                    }
                }
                let section = ContextSection(title: "\(ref.path) — зависимость", body: "````\n" + block + "\n````")
                let proposed = sections + [section]
                if render(sections: proposed, unknowns: unknowns, dropped: dropped).utf8.count > budgetBytes {
                    dropped.append(DroppedSource(
                        path: ref.path,
                        reason: "зависимость не влезает в бюджет \(budgetTokens) токенов"
                    ))
                    continue
                }
                sections.append(section)
                if !included.contains(ref.path) { included.append(ref.path) }
                if let citation = citation(for: ref, block: block) {
                    citations.append(citation)
                }
            }
        }

        // LSP facts (plan item 10): a separate, clearly-sourced section that
        // never duplicates the code blocks above. Absent facts = absent
        // section — the pack continues honestly without LSP.
        if let lspSection {
            sections.append(lspSection)
        }

        // Финальная дедупликация: одинаковые файлы (кандидат + зависимость),
        // точные повторы и смысловые дубли из истории/памяти. Бюджет уже
        // применён, поэтому дедуп только уменьшает пакет.
        let deduped = ContextDeduplication.deduplicate(sections)
        sections = deduped.sections
        dropped.append(contentsOf: deduped.dropped)
        let keptPaths = Set(sections.compactMap { ContextDeduplication.filePath(in: $0) })
        var seenIncluded = Set<String>()
        included = included.filter { keptPaths.contains($0) && seenIncluded.insert($0).inserted }
        // Цитаты обязаны соответствовать блокам, которые реально остались в
        // пакете: после дедупликации фильтр по пути недостаточен (секция
        // «path — зависимость» могла быть выброшена, а её цитата имеет тот же
        // путь). Сверяем диапазон цитаты с заголовком сохранённого блока.
        let keptBlockHeaders = sections.compactMap { section -> String? in
            guard ContextDeduplication.filePath(in: section) != nil else { return nil }
            let lines = section.body.split(separator: "\n")
            guard lines.count >= 2, lines[1].hasPrefix("### ") else { return nil }
            return String(lines[1])
        }
        citations = citations.filter { citation in
            keptBlockHeaders.contains { header in
                header.hasPrefix("### \(citation.path):\(citation.startLine)-\(citation.endLine)")
            }
        }

        // Секция «Чтение файлов»: каждый файл, который НЕ удалось прочитать,
        // назван с причиной (директива 2026-11-13). Показывается в тексте
        // пакета и в спойлере контекста — не «Пробелы», а отдельный честный
        // блок про чтение.
        if !readFailures.isEmpty {
            let body = readFailures.map { "- \($0.path) — \($0.reason)" }
                .joined(separator: "\n")
            sections.append(ContextSection(title: "Чтение файлов", body: body))
        }

        // Never trim the request to fit the evidence budget: losing the user's
        // words is worse than exceeding it. If the request alone is bigger,
        // say so instead of cutting it.
        var text = render(sections: sections, unknowns: unknowns, dropped: dropped, detailedDrop: true)
        if text.utf8.count > budgetBytes {
            unknowns.append("запрос больше бюджета \(budgetTokens) токенов — отправлен целиком")
            text = render(sections: sections, unknowns: unknowns, dropped: dropped, detailedDrop: false)
        }

        return CompiledContextPack(
            sections: sections,
            citations: citations,
            unknowns: unknowns,
            manifest: ContextManifest(included: included, dropped: dropped, considered: candidates.count),
            estimatedTokens: (text.utf8.count + bytesPerToken - 1) / bytesPerToken,
            text: text,
            memoryIDs: memoryIDs,
            ledgerSummary: ledgerSummary,
            planStatus: localPlan?.status,
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Local plan

    /// Deterministic terms come first, then whatever the local planner added.
    /// The model can only widen the query; it can never remove a term the
    /// user's own words produced.
    static func merged(_ base: ContextQueryPlan, with hint: LocalQueryPlan?) -> ContextQueryPlan {
        guard let hint else { return base }
        var terms = base.terms
        for term in hint.terms where !terms.contains(term) { terms.append(term) }
        var symbols = base.symbols
        for symbol in hint.symbols where !symbols.contains(symbol) { symbols.append(symbol) }
        var files = base.files
        for file in hint.files where !files.contains(file) { files.append(file) }
        return ContextQueryPlan(
            terms: terms,
            symbols: symbols,
            files: files,
            lineNumbers: base.lineNumbers
        )
    }

    /// One visible line: which model planned the turn, and what it added.
    /// The fallback case names the reason, so a degraded turn is never
    /// presented as a planned one.
    static func planTraceText(_ result: LocalQueryPlanResult) -> String {
        switch result.status {
        case .local(let model):
            guard let plan = result.plan else { return "источник: \(model)" }
            var parts: [String] = [
                "источник: \(model)",
                "намерение: \(plan.intent.rawValue)"
            ]
            if !plan.files.isEmpty { parts.append("файлы: \(plan.files.joined(separator: ", "))") }
            if !plan.symbols.isEmpty { parts.append("символы: \(plan.symbols.joined(separator: ", "))") }
            if !plan.terms.isEmpty { parts.append("термины: \(plan.terms.joined(separator: ", "))") }
            if !plan.memoryTags.isEmpty { parts.append("теги памяти: \(plan.memoryTags.joined(separator: ", "))") }
            return parts.joined(separator: "; ")
        case .fallback(let reason):
            return "детерминированный план (локальный планировщик: \(reason))"
        }
    }

    // MARK: - Chat history

    /// Compact transcript of the prior chat turns. The chat itself is context
    /// (user directive 2026-10-30): later prompts use the studied data AND
    /// the history; project-less chats use the history as their only context.
    static func historySection(_ turns: [ChatHistoryBuilder.Turn],
                               maxTurns: Int = 40,
                               maxCharsPerTurn: Int = 800) -> ContextSection {
        let cleaned = turns.filter { $0.role == "user" || $0.role == "assistant" }
        let recent = cleaned.count > maxTurns ? Array(cleaned.suffix(maxTurns)) : cleaned
        // User directive 2026-11-08: history enters the pack as a compact
        // thesis chain (done / not-done per the chat's version), not as a raw
        // dump of full messages. Each extracted thesis is short, so we keep
        // many more turns than the old raw 12.
        let body = HistoryCompactifier.compact(recent)
        return ContextSection(title: "История чата", body: body)
    }

    /// Context pack built ONLY from the chat history — for chats without a
    /// project, where previous messages are the only context that exists.
    /// Like `compile`, the user's current message is always included first
    /// (the request is never shortened or hidden).
    static func compileChatHistory(message: String,
                                   turns: [ChatHistoryBuilder.Turn],
                                   budgetTokens: Int = defaultBudgetTokens,
                                   maxTurns: Int = 40,
                                   systemPrompt: String? = nil) -> CompiledContextPack? {
        let request = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = historySection(turns, maxTurns: maxTurns)
        guard !request.isEmpty || !history.body.isEmpty else { return nil }
        var sections = [ContextSection(title: "Запрос", body: request)]
        if !history.body.isEmpty {
            sections.append(history)
        }
        let text = render(sections: sections, unknowns: [], dropped: [])
        return CompiledContextPack(
            sections: sections,
            citations: [],
            unknowns: [],
            manifest: ContextManifest(included: [], dropped: [], considered: 0),
            estimatedTokens: (text.utf8.count + bytesPerToken - 1) / bytesPerToken,
            text: text,
            memoryIDs: [],
            ledgerSummary: nil,
            planStatus: nil,
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Render

    private static func render(sections: [ContextSection],
                               unknowns: [String],
                               dropped: [DroppedSource],
                               detailedDrop: Bool = true) -> String {
        var parts: [String] = []
        for section in sections where section.title != "Запрос" {
            parts.append("## \(section.title)\n\(section.body)")
        }
        if !unknowns.isEmpty {
            parts.append("## Пробелы\n" + unknowns.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !dropped.isEmpty {
            if detailedDrop {
                parts.append("## Не вошло\n" + dropped.map { "- \($0.path) — \($0.reason)" }
                    .joined(separator: "\n"))
            } else {
                parts.append("## Не вошло\n- \(dropped.count) источников (полный список в манифесте)")
            }
        }
        for section in sections where section.title == "Запрос" {
            parts.append("## \(section.title)\n\(section.body)")
        }
        return parts.joined(separator: "\n\n")
    }
}
