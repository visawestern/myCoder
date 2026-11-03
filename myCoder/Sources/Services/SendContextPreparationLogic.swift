import Foundation

/// Why context was (or was not) attached to a turn. The UI uses this to stay
/// quiet when there was simply nothing to collect instead of showing a failure
/// banner on every message.
enum SendContextStatus: Equatable, Sendable {
    /// The feature is off, or the message is blank.
    case disabled
    /// The chat has no project, so there is no project context to collect.
    /// This is a normal state, never a failure.
    case projectless
    /// The compiler ran but nothing matched the request. The model receives
    /// the raw message; no evidence is invented and no error is claimed.
    case noEvidence
    /// A pack with citations/memories/ledger state was assembled.
    case compiled
    /// The project has an index but it could not be read, or it is empty.
    case failed
    /// The first prompt of a chat WITHOUT a project: there is genuinely
    /// nothing to collect yet. Normal state, no warning.
    case projectlessFirstTurn
    /// A project-less chat with history: the previous chat messages ARE the
    /// context (user directive 2026-10-30). Normal state, no warning.
    case chatContext
}

/// What the send path hands to the provider after context compilation.
struct SendContextPreparation: Equatable, Sendable {
    /// Text sent to the model. The visible chat bubble always keeps the raw
    /// user message, so this may differ from what the user typed.
    let modelText: String
    /// The pack that was assembled, when compilation ran.
    let pack: CompiledContextPack?
    /// Visible reason when the context could not be assembled. Sending still
    /// proceeds — a compiler failure must never block the user.
    let warning: String?
    /// Why the pack is (not) here. `noEvidence` and `projectless` are normal,
    /// so neither produces a warning banner.
    let status: SendContextStatus
}

enum SendContextPreparationLogic {

    static func prepare(message: String,
                        records: [FileIndexRecord],
                        projectPath: String,
                        isEnabled: Bool,
                        memories: [ProjectMemoryChunk] = [],
                        ledger: TaskLedger? = nil,
                        extraWarning: String? = nil,
                        localPlan: LocalQueryPlanResult? = nil,
                        board preparedBoard: ContextBoard? = nil,
                        priorTurns: [ChatHistoryBuilder.Turn] = [],
                        isPlanMode: Bool = false,
                        systemPrompt: String? = nil,
                        skillsDirectory: URL? = nil,
                        impact: ImpactReport? = nil,
                        onStage: (@Sendable (ContextStageLogLogic.Stage) -> Void)? = nil,
                        budgetTokens: Int = TurnContextCompiler.defaultBudgetTokens) -> SendContextPreparation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else {
            return SendContextPreparation(modelText: message, pack: nil,
                                          warning: extraWarning, status: .disabled)
        }
        // An open project supplies evidence even before the first chat turn.
        guard !projectPath.isEmpty || !priorTurns.isEmpty || isPlanMode else {
            return SendContextPreparation(modelText: message, pack: nil,
                                          warning: extraWarning, status: .projectlessFirstTurn)
        }
        // A chat without a project: the previous chat messages are the only
        // context that exists. They are compiled into a chat-history pack.
        // Warning here fired on every message in "Без проекта" even though
        // nothing was wrong — the send is complete without project evidence.
        guard !projectPath.isEmpty else {
            if let pack = TurnContextCompiler.compileChatHistory(message: message, turns: priorTurns, systemPrompt: systemPrompt) {
                return SendContextPreparation(modelText: pack.text, pack: pack,
                                              warning: extraWarning, status: .chatContext)
            }
            return SendContextPreparation(modelText: message, pack: nil,
                                          warning: combinedWarning(nil, extraWarning),
                                          status: .projectless)
        }
        let board = preparedBoard ?? ContextBoardBuilder.build(projectPath: projectPath, records: records)
        let pack = TurnContextCompiler.compile(
            message: trimmed,
            board: board,
            projectRoot: projectPath,
            memories: memories,
            ledger: ledger,
            chatHistory: priorTurns,
            budgetTokens: budgetTokens,
            localPlan: localPlan,
            systemPrompt: systemPrompt,
            skillsDirectory: skillsDirectory,
            records: records,
            impact: impact,
            onStage: onStage
        )
        // Keep the task history, project rules, model fallback and known gaps
        // even when no source file matched. Absence of code is visible in the pack.
        let hasEvidence = !pack.citations.isEmpty || !pack.memoryIDs.isEmpty || pack.ledgerSummary != nil
        return SendContextPreparation(
            modelText: pack.text,
            pack: pack,
            warning: combinedWarning(nil, extraWarning),
            status: hasEvidence ? .compiled : .noEvidence
        )
    }

    private static func combinedWarning(_ first: String?, _ second: String?) -> String? {
        let parts = [first, second].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// True when the model should receive the ledger instead of the raw prior
    /// turns. The ledger itself already lives in the pack text.
    static func replacesRawHistory(_ preparation: SendContextPreparation,
                                   priorTurnCount: Int) -> Bool {
        TaskLedgerPolicy.replacesRawHistory(
            summary: preparation.pack?.ledgerSummary,
            priorTurnCount: priorTurnCount
        )
    }

    /// The chat part that carries the pack behind the "Контекст" button.
    /// Empty when no pack was built, so a plain message stays a plain message.
    /// The audit text (system instruction + context + request) is stored, not
    /// the wire text, so the viewer shows the whole payload the model saw.
    static func contextParts(_ preparation: SendContextPreparation) -> [MessagePartContent] {
        guard let pack = preparation.pack, !pack.auditText.isEmpty else { return [] }
        return [.compiledContext(pack.auditText)]
    }

    /// Same as `prepare`, off the main thread: ranking and reading files are
    /// synchronous disk work and must not freeze the composer. The caller owns
    /// the "compiling" state so the UI can show it.
    static func prepareAsync(message: String,
                            records: [FileIndexRecord],
                            projectPath: String,
                            isEnabled: Bool,
                            memories: [ProjectMemoryChunk] = [],
                            ledger: TaskLedger? = nil,
                            extraWarning: String? = nil,
                            localPlan: LocalQueryPlanResult? = nil,
                            board: ContextBoard? = nil,
                            priorTurns: [ChatHistoryBuilder.Turn] = [],
                            isPlanMode: Bool = false,
                            systemPrompt: String? = nil,
                            skillsDirectory: URL? = nil,
                            impact: ImpactReport? = nil,
                            onStage: (@Sendable (ContextStageLogLogic.Stage) -> Void)? = nil,
                            budgetTokens: Int = TurnContextCompiler.defaultBudgetTokens) async -> SendContextPreparation {
        await Task.detached(priority: .userInitiated) {
            prepare(
                message: message,
                records: records,
                projectPath: projectPath,
                isEnabled: isEnabled,
                memories: memories,
                ledger: ledger,
                extraWarning: extraWarning,
                localPlan: localPlan,
                board: board,
                priorTurns: priorTurns,
                isPlanMode: isPlanMode,
                systemPrompt: systemPrompt,
                skillsDirectory: skillsDirectory,
                impact: impact,
                onStage: onStage,
                budgetTokens: budgetTokens
            )
        }.value
    }

    /// Human-readable summary of what context compilation did (or why it did
    /// nothing). Shown in the "Контекст" sheet so the user never sees an
    /// empty window: either the collected pack's contents, or an honest
    /// reason (first turn, project-less chat, no evidence, error, disabled).
    static func summary(_ preparation: SendContextPreparation) -> String {
        switch preparation.status {
        case .compiled:
            guard let pack = preparation.pack else {
                return "Собран точечный контекст."
            }
            var facts: [String] = []
            if !pack.manifest.included.isEmpty {
                facts.append("файлов: \(pack.manifest.included.count)")
            }
            if !pack.memoryIDs.isEmpty {
                facts.append("память: \(pack.memoryIDs.count)")
            }
            if let ledger = pack.ledgerSummary, !ledger.isEmpty {
                facts.append("состояние задачи")
            }
            if facts.isEmpty {
                facts.append("\(pack.text.utf8.count) Б")
            }
            return "Собран точечный контекст: " + facts.joined(separator: ", ")
        case .chatContext:
            return "Проект не открыт — контекст собран из истории чата."
        case .projectlessFirstTurn:
            return "Первый промпт в чате — контекст не собирался (правило: ещё нечего собирать)."
        case .projectless:
            return "Чат без проекта — точечного проектного контекста нет."
        case .noEvidence:
            return "Совпадений в коде не найдено — отправлены доступные инструкции, история и пробелы контекста."
        case .failed:
            return preparation.warning ?? "Ошибка сборки контекста."
        case .disabled:
            return "Точечный контекст выключен."
        }
    }
}
