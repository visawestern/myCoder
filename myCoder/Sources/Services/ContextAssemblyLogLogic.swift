import Foundation

/// The complete, honest log of one context-assembly run.
///
/// User directive 2026-11-07: the composer status line becomes an upward
/// spoiler that lists every action the host really performed while building
/// the context. Each action keeps three parts — what was requested, how it
/// was processed and what came back — so a turn can be audited instead of
/// taken on faith. Nothing here is synthesized: every value comes from the
/// real pipeline (index, memory, ledger, planner, impact, skills, graph,
/// files, final pack).
enum ContextAssemblyLogLogic {

    enum Status: String, Equatable, Sendable {
        case running
        case done
        case warning
        case failed
        case skipped
    }

    // Stable keys. The UI never shows them; they only let a stage update its
    // own row instead of appending a second copy.
    static let requestKey = "request"
    static let indexKey = "index"
    static let memoryKey = "memory"
    static let ledgerKey = "ledger"
    static let planningKey = "planning"
    static let systemKey = "system"
    static let impactKey = "impact"
    static let skillsKey = "skills"
    static let graphKey = "graph"
    static let filesKey = "files"
    static let packKey = "pack"

    struct Entry: Identifiable, Equatable, Sendable {
        let id: UUID
        let key: String
        let title: String
        /// What the host asked for / read / planned.
        var request: String
        /// What the host did with it.
        var processing: String
        /// What actually came back.
        var result: String
        var status: Status
        let startedAt: Date
        var finishedAt: Date?

        init(key: String,
             title: String,
             request: String,
             processing: String,
             result: String = "",
             status: Status = .running,
             startedAt: Date = Date(),
             finishedAt: Date? = nil) {
            self.id = UUID()
            self.key = key
            self.title = title
            self.request = request
            self.processing = processing
            self.result = result
            self.status = status
            self.startedAt = startedAt
            self.finishedAt = finishedAt
        }

        var durationMilliseconds: Int? {
            guard let finishedAt else { return nil }
            return max(0, Int((finishedAt.timeIntervalSince(startedAt) * 1000).rounded()))
        }
    }

    struct Log: Equatable, Sendable {
        var entries: [Entry]
        var isRunning: Bool
        var startedAt: Date?
        var finishedAt: Date?
        var summary: String

        static let empty = Log(entries: [], isRunning: false, startedAt: nil, finishedAt: nil, summary: "")

        var hasEntries: Bool { !entries.isEmpty }
        var hasProblems: Bool {
            entries.contains { $0.status == .warning || $0.status == .failed }
        }
    }

    /// Everything the final pass needs to settle the log. All of it is real
    /// pipeline state — no guesses.
    struct Facts: Equatable, Sendable {
        let preparation: SendContextPreparation
        let projectRoot: String
        let contextEnabled: Bool
        let plannerEnabled: Bool
        let impact: ImpactReport?
        let impactTimedOut: Bool
        let systemPromptBytes: Int
        let historyTurnCount: Int
    }

    // MARK: - Lifecycle

    static func begin(message: String, projectRoot: String, now: Date = Date()) -> Log {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = trimmed.isEmpty ? "(пустой запрос)" : trimmed
        let processing = projectRoot.isEmpty
            ? "Фиксирую запрос и историю чата (проект не открыт)"
            : "Фиксирую запрос, историю чата и границы проекта: \(projectRoot)"
        let entry = Entry(
            key: requestKey,
            title: "Запрос и история",
            request: request,
            processing: processing,
            status: .running,
            startedAt: now
        )
        return Log(entries: [entry], isRunning: true, startedAt: now, finishedAt: nil, summary: "")
    }

    /// Starts an action. An action that is already known keeps its first
    /// request — the compiler reports a stage the send path may have started
    /// earlier, and that must not become two rows.
    static func start(key: String,
                      title: String,
                      request: String,
                      processing: String,
                      now: Date = Date(),
                      in log: Log) -> Log {
        guard !log.entries.contains(where: { $0.key == key }) else { return log }
        var updated = log
        updated.entries.append(Entry(
            key: key,
            title: title,
            request: request,
            processing: processing,
            status: .running,
            startedAt: now
        ))
        return updated
    }

    /// Finishes a known action with its real outcome.
    static func finish(key: String,
                       result: String,
                       status: Status = .done,
                       now: Date = Date(),
                       in log: Log) -> Log {
        guard let index = log.entries.firstIndex(where: { $0.key == key }) else { return log }
        var updated = log
        updated.entries[index].result = result
        updated.entries[index].status = status
        updated.entries[index].finishedAt = now
        return updated
    }

    /// Settles an action that may not exist yet: skipped stages are added with
    /// their reason instead of silently missing from the log. An action that
    /// already carries a real result keeps it — the final pass must not
    /// overwrite what the pipeline actually reported.
    static func settle(key: String,
                       title: String,
                       request: String = "",
                       processing: String = "",
                       result: String,
                       status: Status,
                       now: Date = Date(),
                       in log: Log) -> Log {
        var updated = log
        if let index = updated.entries.firstIndex(where: { $0.key == key }) {
            if updated.entries[index].status == .running {
                updated.entries[index].result = result.isEmpty ? "Стадия не завершила работу." : result
                updated.entries[index].status = status
                updated.entries[index].finishedAt = now
            }
            if updated.entries[index].request.isEmpty && !request.isEmpty {
                updated.entries[index].request = request
            }
            if updated.entries[index].processing.isEmpty && !processing.isEmpty {
                updated.entries[index].processing = processing
            }
            return updated
        }
        updated.entries.append(Entry(
            key: key,
            title: title,
            request: request,
            processing: processing,
            result: result.isEmpty ? "Стадия не завершила работу." : result,
            status: status,
            startedAt: now,
            finishedAt: now
        ))
        return updated
    }

    /// Overwrites the outcome of an action — used for the final pack, whose
    /// result is known only after everything else has run.
    static func set(key: String,
                    result: String,
                    status: Status,
                    now: Date = Date(),
                    in log: Log) -> Log {
        var updated = log
        if let index = updated.entries.firstIndex(where: { $0.key == key }) {
            updated.entries[index].result = result
            updated.entries[index].status = status
            updated.entries[index].finishedAt = now
            return updated
        }
        return updated
    }

    // MARK: - Titles

    static func title(for stage: ContextStageLogLogic.Stage) -> String {
        switch stage {
        case .planning: return "Планировщик запроса"
        case .index: return "Индекс проекта"
        case .memory: return "Память проекта"
        case .graph: return "Граф кода"
        case .skills: return "Скиллы"
        case .impact: return "Связи и зависимости"
        case .files: return "Чтение файлов"
        }
    }

    // MARK: - Final pass

    /// Settles every action of the run and closes the log. The pack is the
    /// only source of truth for what ended up in the payload.
    static func finalize(log: Log, facts: Facts, now: Date = Date()) -> Log {
        var updated = log
        let pack = facts.preparation.pack
        let hasProject = !facts.projectRoot.isEmpty
        let projectStagesRan = facts.contextEnabled && hasProject && pack != nil
        let skipReason = projectStageSkipReason(facts)

        if projectStagesRan {
            for (key, title) in [
                (indexKey, "Индекс проекта"),
                (memoryKey, "Память проекта"),
                (ledgerKey, "Состояние задачи")
            ] {
                updated = settle(key: key,
                                 title: title,
                                 result: "Стадия не дала результата.",
                                 status: .warning,
                                 now: now,
                                 in: updated)
            }
        } else {
            for (key, title) in [
                (indexKey, "Индекс проекта"),
                (memoryKey, "Память проекта"),
                (ledgerKey, "Состояние задачи")
            ] {
                updated = settle(key: key,
                                 title: title,
                                 result: skipReason,
                                 status: .skipped,
                                 now: now,
                                 in: updated)
            }
        }

        // Planning
        if facts.contextEnabled, facts.plannerEnabled, hasProject {
            updated = settle(key: planningKey,
                             title: "Планировщик запроса",
                             result: "Планировщик не вернул результата — использован детерминированный план.",
                             status: .warning,
                             now: now,
                             in: updated)
        } else {
            let reason: String
            if !facts.contextEnabled {
                reason = "Точечный контекст выключен."
            } else if !facts.plannerEnabled {
                reason = "Локальный планировщик выключен."
            } else {
                reason = "Чат без проекта: планировать нечего."
            }
            updated = settle(key: planningKey,
                             title: "Планировщик запроса",
                             result: reason,
                             status: .skipped,
                             now: now,
                             in: updated)
        }

        // System instruction
        updated = settle(key: systemKey,
                         title: "Системная инструкция",
                         request: "Системная инструкция текущего хода",
                         processing: "Собираю правила проекта, режим работы и правила провайдера",
                         result: facts.systemPromptBytes > 0
                            ? "Инструкция: \(facts.systemPromptBytes) Б."
                            : "Системная инструкция пуста.",
                         status: facts.systemPromptBytes > 0 ? .done : .warning,
                         now: now,
                         in: updated)

        // Impact
        if projectStagesRan {
            let (text, status) = impactResult(facts.impact, timedOut: facts.impactTimedOut)
            updated = settle(key: impactKey,
                             title: "Связи и зависимости",
                             result: text,
                             status: status,
                             now: now,
                             in: updated)
        } else {
            updated = settle(key: impactKey,
                             title: "Связи и зависимости",
                             result: skipReason,
                             status: .skipped,
                             now: now,
                             in: updated)
        }

        // Skills / graph / files — the three sources the compiler reads.
        if let pack {
            let (skillsText, skillsStatus) = skillsResult(sections: pack.sections)
            updated = settle(key: skillsKey,
                             title: "Скиллы",
                             result: skillsText,
                             status: skillsStatus,
                             now: now,
                             in: updated)
            let (graphText, graphStatus) = graphResult(sections: pack.sections)
            updated = settle(key: graphKey,
                             title: "Граф кода",
                             result: graphText,
                             status: graphStatus,
                             now: now,
                             in: updated)
            let (filesText, filesStatus) = filesResult(manifest: pack.manifest, unknowns: pack.unknowns)
            updated = settle(key: filesKey,
                             title: "Чтение файлов",
                             result: filesText,
                             status: filesStatus,
                             now: now,
                             in: updated)
        } else {
            for (key, title) in [
                (skillsKey, "Скиллы"),
                (graphKey, "Граф кода"),
                (filesKey, "Чтение файлов")
            ] {
                updated = settle(key: key,
                                 title: title,
                                 result: skipReason,
                                 status: .skipped,
                                 now: now,
                                 in: updated)
            }
        }

        // The pack itself.
        let (packText, packStatus) = packResult(facts.preparation)
        updated = settle(key: packKey,
                         title: "Итоговый пакет",
                         request: "Системная инструкция: \(facts.systemPromptBytes) Б; история: \(facts.historyTurnCount) ход(ов)",
                         processing: "Склеиваю секции, проверяю бюджет и считаю токены",
                         result: packText,
                         status: packStatus,
                         now: now,
                         in: updated)
        updated = set(key: packKey,
                      result: packText,
                      status: packStatus,
                      now: now,
                      in: updated)

        // Nothing may stay "running" after the turn: an unfinished stage is a
        // visible gap, not a silent one.
        for index in updated.entries.indices where updated.entries[index].status == .running {
            updated.entries[index].status = .warning
            updated.entries[index].result = updated.entries[index].result.isEmpty
                ? "Стадия не завершила работу."
                : updated.entries[index].result
            updated.entries[index].finishedAt = updated.entries[index].finishedAt ?? now
        }
        updated.isRunning = false
        updated.finishedAt = now
        updated.summary = SendContextPreparationLogic.summary(facts.preparation)
        return updated
    }

    private static func projectStageSkipReason(_ facts: Facts) -> String {
        if !facts.contextEnabled {
            return "Точечный контекст выключен."
        }
        if facts.projectRoot.isEmpty {
            return "Чат без проекта: проектных источников нет."
        }
        return "Пакет не собран: \(SendContextPreparationLogic.summary(facts.preparation))"
    }

    // MARK: - Results

    static func planningResult(_ result: LocalQueryPlanResult?) -> (String, Status) {
        guard let result else {
            return ("Локальный планировщик не вернул результата — использован детерминированный план.", .warning)
        }
        switch result.status {
        case .local:
            return (TurnContextCompiler.planTraceText(result), .done)
        case .fallback:
            return (TurnContextCompiler.planTraceText(result), .warning)
        }
    }

    static func skillsResult(sections: [ContextSection]) -> (String, Status) {
        let skills = sections.filter { $0.title.hasPrefix("Скилл:") }
        guard !skills.isEmpty else {
            return ("Подходящих скиллов нет — секция не добавлена.", .warning)
        }
        let names = skills.map { String($0.title.dropFirst("Скилл: ".count)) }
        return ("Скиллов: \(skills.count)\n" + names.map { "- \($0)" }.joined(separator: "\n"), .done)
    }

    static func graphResult(sections: [ContextSection]) -> (String, Status) {
        guard let graph = sections.first(where: { $0.title == "Граф кода" }) else {
            return ("Секция графа не добавлена: индекс пуст или стадия не запускалась.", .warning)
        }
        if graph.body.contains("нет символов, подходящих под запрос") {
            return ("Символов по запросу не найдено — граф пуст.", .warning)
        }
        return (graph.body, .done)
    }

    static func filesResult(manifest: ContextManifest, unknowns: [String]) -> (String, Status) {
        var lines: [String] = ["Кандидатов проверено: \(manifest.considered)"]
        if manifest.included.isEmpty {
            lines.append("В пакет не попал ни один файл.")
        } else {
            lines.append("Файлов в пакете: \(manifest.included.count)")
            lines.append(contentsOf: manifest.included.map { "- \($0)" })
        }
        if !manifest.dropped.isEmpty {
            lines.append("Отброшено: \(manifest.dropped.count)")
            lines.append(contentsOf: manifest.dropped.map { "- \($0.path) — \($0.reason)" })
        }
        if !unknowns.isEmpty {
            lines.append("Пробелы в контексте:")
            lines.append(contentsOf: unknowns.map { "- \($0)" })
        }
        let status: Status = manifest.included.isEmpty || !manifest.dropped.isEmpty ? .warning : .done
        return (lines.joined(separator: "\n"), status)
    }

    static func impactResult(_ impact: ImpactReport?, timedOut: Bool) -> (String, Status) {
        if timedOut {
            return ("Бюджет анализа связей истёк — продолжил без отчёта о зависимостях.", .warning)
        }
        guard let impact else {
            return ("Отчёт о связях не построен.", .warning)
        }
        if impact.isEmpty {
            return ("Подтверждённых связей нет. Это не доказывает отсутствие зависимостей.", .warning)
        }
        var lines: [String] = []
        if !impact.triggers.isEmpty {
            lines.append("Признаки изменения: \(impact.triggers.joined(separator: ", "))")
        }
        lines.append("Кандидатов ядра: \(impact.affected.count)")
        lines.append("Зависимостей: \(impact.dependents.count)")
        lines.append("Решений по связям: \(impact.fates.count)")
        lines.append("Вопросов: \(impact.questions.count)")
        for dependency in impact.dependents {
            let location = dependency.startLine.map { ":\($0)" } ?? ""
            lines.append("- \(dependency.kind) \(dependency.name) — \(dependency.path)\(location) [\(dependency.edge.rawValue)]")
        }
        return (lines.joined(separator: "\n"), .done)
    }

    static func packResult(_ preparation: SendContextPreparation) -> (String, Status) {
        guard let pack = preparation.pack else {
            let status: Status
            switch preparation.status {
            case .failed: status = .failed
            case .disabled, .projectless, .projectlessFirstTurn: status = .skipped
            default: status = .warning
            }
            return (SendContextPreparationLogic.summary(preparation), status)
        }
        var lines: [String] = []
        lines.append("Секций: \(pack.sections.count)")
        lines.append("Файлов: \(pack.manifest.included.count)")
        lines.append("Память: \(pack.memoryIDs.count)")
        lines.append("Цитат: \(pack.citations.count)")
        lines.append("Оценка: \(pack.estimatedTokens) токенов")
        lines.append("Полный payload: \(pack.auditText.utf8.count) Б")
        if let ledger = pack.ledgerSummary, !ledger.isEmpty {
            lines.append("Состояние задачи: есть")
        }
        if !pack.unknowns.isEmpty {
            lines.append("Пробелы: \(pack.unknowns.count)")
        }
        if let warning = preparation.warning, !warning.isEmpty {
            lines.append("Предупреждение: \(warning)")
        }
        let status: Status
        switch preparation.status {
        case .compiled, .chatContext: status = .done
        case .failed: status = .failed
        case .disabled, .projectless, .projectlessFirstTurn: status = .skipped
        case .noEvidence: status = .warning
        }
        return (lines.joined(separator: "\n"), status)
    }
}
