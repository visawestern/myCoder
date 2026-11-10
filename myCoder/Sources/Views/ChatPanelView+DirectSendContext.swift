import SwiftUI
import AppKit

/// Evidence collected for one direct-send turn. Kept as a value so the
/// collection stage can live in its own module without widening the send
/// function past the 600-line budget.
struct DirectSendContextCollection {
    var pointContextRecords: [FileIndexRecord] = []
    var projectMemories: [ProjectMemoryChunk] = []
    var taskLedger: TaskLedger?
    var contextWarning: String?
    var localPlan: LocalQueryPlanResult?
    var preparedBoard: ContextBoard?
    var impactReport: ImpactReport?
    var impactTimedOut = false
}

extension ChatPanelView {
    /// Collects index/memory/ledger/board/planner/impact evidence for a turn.
    /// Returns plain values; the caller owns presentation and history building.
    func collectDirectSendContext(
        projectRoot: String,
        hasProject: Bool,
        needsContextPrep: Bool,
        sendSessionID: String?,
        turnSessionID: String?,
        agentMode: AgentMode,
        priorTurnsForContext: [ChatHistoryBuilder.Turn],
        text: String
    ) async -> DirectSendContextCollection {
        let pointContextProjectRoot = projectRoot
        let hasProjectForContext = hasProject
        var pointContextRecords: [FileIndexRecord] = []
        var projectMemories: [ProjectMemoryChunk] = []
        var taskLedger: TaskLedger?
        var contextWarning: String?
        // The whole context collection — index, memory, ledger, board, planner,
        // impact, compilation — shares one five-minute ceiling (user directive
        // 2026-11-08). Every stage below spends from what is left of it, so
        // the stages can no longer add up to more than five minutes.
        let contextCollectionStartedAt = Date()
        if appState.isPointContextEnabled && hasProjectForContext && needsContextPrep {
            await MainActor.run { appState.beginContextCompilation(sessionID: sendSessionID) }
            await MainActor.run {
                appState.setContextStage(
                    ContextStageLogLogic.line(for: .index),
                    sessionID: sendSessionID
                )
                appState.startContextAction(
                    key: ContextAssemblyLogLogic.indexKey,
                    title: ContextAssemblyLogLogic.title(for: .index),
                    request: "Корень проекта: \(pointContextProjectRoot)",
                    processing: ContextStageLogLogic.line(for: .index),
                    sessionID: sendSessionID
                )
            }
            pointContextRecords = await Self.recordsForPointContext(projectPath: pointContextProjectRoot)
            await MainActor.run {
                appState.finishContextAction(
                    key: ContextAssemblyLogLogic.indexKey,
                    result: pointContextRecords.isEmpty
                        ? "Индекс пуст: файлов в индексе 0."
                        : "Файлов в индексе: \(pointContextRecords.count).",
                    status: pointContextRecords.isEmpty ? .warning : .done,
                    sessionID: sendSessionID
                )
            }
            // Memory lives in the project database. A read failure must be
            // visible: sending without the facts the user saved would answer
            // from a wrong assumption.
            await MainActor.run {
                appState.setContextStage(
                    ContextStageLogLogic.line(
                        for: .memory,
                        detail: pointContextRecords.isEmpty ? "" : "файлов в индексе: \(pointContextRecords.count)"
                    ),
                    sessionID: sendSessionID
                )
                appState.startContextAction(
                    key: ContextAssemblyLogLogic.memoryKey,
                    title: ContextAssemblyLogLogic.title(for: .memory),
                    request: "Память проекта: \(pointContextProjectRoot)",
                    processing: ContextStageLogLogic.line(for: .memory),
                    sessionID: sendSessionID
                )
            }
            var memoryLoadFailed = false
            do {
                projectMemories = try await Task.detached(priority: .utility) {
                    try ProjectMemoryStore.loadChunks(projectPath: pointContextProjectRoot)
                }.value
            } catch {
                memoryLoadFailed = true
                contextWarning = L.t(AppLocalizationKey.locMemoryLoadFailed)
            }
            await MainActor.run {
                appState.finishContextAction(
                    key: ContextAssemblyLogLogic.memoryKey,
                    result: memoryLoadFailed
                        ? "Память проекта не прочитана: \(L.t(AppLocalizationKey.locMemoryLoadFailed))"
                        : "Чанков памяти: \(projectMemories.count).",
                    status: memoryLoadFailed ? .warning : .done,
                    sessionID: sendSessionID
                )
            }

            // The ledger is append-only: it merges the persisted state with the
            // messages still visible, so a pruned feed cannot forget an earlier
            // constraint. Session ids are assigned before the first append, so
            // a brand-new session simply has no ledger yet.
            let ledgerSessionID = turnSessionID ?? ""
            if !ledgerSessionID.isEmpty {
                await MainActor.run {
                    appState.startContextAction(
                        key: ContextAssemblyLogLogic.ledgerKey,
                        title: "Состояние задачи",
                        request: "Сессия: \(ledgerSessionID); цель: \(appState.currentSessionGoal ?? "не задана")",
                        processing: "Читаю сохранённое состояние задачи и объединяю его с видимыми ходами",
                        sessionID: sendSessionID
                    )
                }
                var persisted: TaskLedger?
                do {
                    persisted = try await Task.detached(priority: .utility) {
                        try TaskLedgerStore.load(
                            projectPath: pointContextProjectRoot,
                            sessionID: ledgerSessionID
                        )
                    }.value
                } catch {
                    contextWarning = [contextWarning, L.t(AppLocalizationKey.locLedgerFailed)]
                        .compactMap { $0 }.joined(separator: "\n")
                }

                let ledger = TaskLedgerExtraction.build(
                    sessionID: ledgerSessionID,
                    projectPath: pointContextProjectRoot,
                    goal: appState.currentSessionGoal,
                    messages: messageStore.messages(in: turnSessionID),
                    memories: projectMemories,
                    previous: persisted
                )
                taskLedger = ledger.isEmpty ? persisted : ledger

                if let taskLedger {
                    do {
                        try await Task.detached(priority: .utility) {
                            try TaskLedgerStore.save(taskLedger)
                        }.value
                    } catch {
                        contextWarning = [contextWarning, L.t(AppLocalizationKey.locLedgerFailed)]
                            .compactMap { $0 }.joined(separator: "\n")
                    }
                }
                await MainActor.run {
                    appState.finishContextAction(
                        key: ContextAssemblyLogLogic.ledgerKey,
                        result: taskLedger.map { ledger in
                            let summary = ledger.summaryText
                            return summary.isEmpty
                                ? "Состояние задачи пустое."
                                : "Состояние задачи: \(summary.count) символов."
                        } ?? "Состояние задачи не найдено.",
                        status: taskLedger == nil ? .warning : .done,
                        sessionID: sendSessionID
                    )
                }
            }
        }
        // The optional local planner runs before compilation and only widens
        // the deterministic plan: it names entities from a bounded list, and
        // any failure is reported as a fallback instead of blocking the send.
        var localPlan: LocalQueryPlanResult?
        var preparedBoard: ContextBoard?
        if appState.isPointContextEnabled, appState.isLocalQueryPlannerEnabled,
           hasProjectForContext, needsContextPrep {
            // Board building extracts symbols/imports/tokens from every indexed
            // file — heavy CPU on the main actor froze the UI for seconds at
            // send start (user report 2026-10-30). Build it off-main and under
            // what is left of the shared collection budget.
            let boardBudget = ContextCollectionBudget.stageBudget(
                ownLimit: ImpactBudget.defaultBudget,
                startedAt: contextCollectionStartedAt
            )
            let board: ContextBoard? = await ImpactBudget.runSync(budget: .seconds(boardBudget)) {
                ContextBoardBuilder.build(
                    projectPath: pointContextProjectRoot,
                    records: pointContextRecords
                )
            }
            preparedBoard = board
            // The local planner runs a local model and can take seconds — run
            // it off the main actor so the UI stays responsive while it works
            // (user directive 2026-10-29, §16.2).
            await MainActor.run {
                appState.setContextStage(
                    ContextStageLogLogic.line(for: .planning),
                    sessionID: sendSessionID
                )
                appState.startContextAction(
                    key: ContextAssemblyLogLogic.planningKey,
                    title: ContextAssemblyLogLogic.title(for: .planning),
                    request: "Запрос: \(text)",
                    processing: ContextStageLogLogic.line(for: .planning),
                    sessionID: sendSessionID
                )
            }
            // The planner spends from the shared budget too: its own 20 s and
            // the five-minute ceiling, whichever is smaller.
            let planningBudget = ContextCollectionBudget.stageBudget(
                ownLimit: InternalContextPlanner.defaultBudget,
                startedAt: contextCollectionStartedAt
            )
            // M1: in per-role routing mode the planner runs on the .planning
            // role's model (nil in single mode keeps the internal model).
            let planningComplete = routedPlanningComplete(agentMode: agentMode, sessionID: sendSessionID)
            localPlan = await Task.detached(priority: .utility) {
                await TurnContextPlanningService.plan(
                    message: text,
                    board: board ?? ContextBoard(projectPath: pointContextProjectRoot,
                                                 entries: [],
                                                 builtAt: Date()),
                    memories: projectMemories,
                    records: pointContextRecords,
                    priorTurns: priorTurnsForContext,
                    ledger: taskLedger,
                    budget: planningBudget,
                    complete: planningComplete
                )
            }.value
            let planningOutcome = ContextAssemblyLogLogic.planningResult(localPlan)
            await MainActor.run {
                appState.finishContextAction(
                    key: ContextAssemblyLogLogic.planningKey,
                    result: planningOutcome.0,
                    status: planningOutcome.1,
                    sessionID: sendSessionID
                )
            }
        }
        // Harness pass: a structural change ("хранилище переехало", "раздел
        // больше не нужен") must arrive with its reverse edges and the
        // questions that force a decision on each one. Deterministic host
        // work over the code graph — the internal model only widens the plan.
        var impactReport: ImpactReport?
        var impactTimedOut = false
        if appState.isPointContextEnabled, hasProjectForContext, needsContextPrep {
            await MainActor.run {
                appState.setContextStage(
                    ContextStageLogLogic.line(for: .impact),
                    sessionID: sendSessionID
                )
                appState.startContextAction(
                    key: ContextAssemblyLogLogic.impactKey,
                    title: ContextAssemblyLogLogic.title(for: .impact),
                    request: "Запрос: \(text)",
                    processing: ContextStageLogLogic.line(for: .impact),
                    sessionID: sendSessionID
                )
            }
            let impactQuery = {
                let plan = ContextQueryPlanner.plan(for: text)
                return (plan.terms + plan.symbols).joined(separator: " ")
            }()
            // Бюджет обязателен: report() переиндексирует проект синхронно и
            // без предела. Живой прогон 2026-11-04 (чат FF5D0A17) встал на
            // этой стадии и ход не дал ответа вообще. Проход — необязательные
            // улики: по истечении бюджета идём дальше с тем графом, что есть.
            let impactRoot = pointContextProjectRoot
            let impactRecords = pointContextRecords
            let impactIntent = localPlan?.plan?.intent
            let impactTerms = (localPlan?.plan?.terms ?? []) + (localPlan?.plan?.symbols ?? []) + (localPlan?.plan?.files ?? [])
            let messageText = text
            // The impact pass gets what is left of the shared five-minute
            // collection budget — not its own full 300 s on top of the stages
            // that already ran (user directive 2026-11-08).
            let impactBudget = ContextCollectionBudget.stageBudget(
                ownLimit: ImpactBudget.defaultBudget,
                startedAt: contextCollectionStartedAt
            )
            let impactResult: ImpactReport?? = await ImpactBudget.runSync(budget: .seconds(impactBudget)) { () -> ImpactReport? in
                do {
                    return try ImpactAnalyzer.report(
                        projectPath: impactRoot,
                        message: messageText,
                        query: impactQuery,
                        records: impactRecords,
                        intent: impactIntent,
                        semanticTerms: impactTerms
                    ) ?? ImpactAnalyzer.analyze(message: messageText, seeds: [], graph: .empty,
                                                 intent: impactIntent)
                } catch {
                    return ImpactAnalyzer.analyze(message: messageText, seeds: [], graph: .empty,
                                                  intent: impactIntent)
                }
            }
            impactReport = impactResult ?? nil
            impactTimedOut = impactResult == nil
            let impactOutcome = ContextAssemblyLogLogic.impactResult(impactReport, timedOut: impactTimedOut)
            await MainActor.run {
                appState.finishContextAction(
                    key: ContextAssemblyLogLogic.impactKey,
                    result: impactOutcome.0,
                    status: impactOutcome.1,
                    sessionID: sendSessionID
                )
            }
        }
        return DirectSendContextCollection(
            pointContextRecords: pointContextRecords,
            projectMemories: projectMemories,
            taskLedger: taskLedger,
            contextWarning: contextWarning,
            localPlan: localPlan,
            preparedBoard: preparedBoard,
            impactReport: impactReport,
            impactTimedOut: impactTimedOut
        )
    }
}
