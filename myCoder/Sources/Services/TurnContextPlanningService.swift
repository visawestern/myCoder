import Foundation

/// Shared planning inputs for real sends and context preview.
enum TurnContextPlanningService {
    static func plan(message: String,
                                    board: ContextBoard,
                                    memories: [ProjectMemoryChunk],
                                    records: [FileIndexRecord],
                                    priorTurns: [ChatHistoryBuilder.Turn],
                                    ledger: TaskLedger?,
                                    budget: TimeInterval = InternalContextPlanner.defaultBudget,
                                    complete: (@Sendable ([DirectChatMessage]) async throws -> String)? = nil) async -> LocalQueryPlanResult {
        let skillsRoot = MyCoderPaths.skillsDir(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let catalog = TurnEvidence.skillCatalog(directory: skillsRoot)
        let recent = TurnContextCompiler.historySection(priorTurns).body
        let facts = ProjectMemoryRanker.rank(memories, query: message, limit: 5)
            .map { "[\($0.kind)] \($0.text)" }.joined(separator: "\n")
        let taskContext = taskEvidence(history: recent, ledger: ledger?.summaryText ?? "", facts: facts,
                                       rules: TurnEvidence.projectInstructions(projectPath: board.projectPath)?.body ?? "",
                                       skills: catalog.map { "Skill \($0.id): \($0.summary)" }.joined(separator: "\n"))
        let graphContext = (try? TurnEvidence.graph(projectPath: board.projectPath,
                                                    query: message, records: records).body)
            ?? "Граф недоступен; проверь зависимости поиском в коде."
        let context = LocalPlannerContextBuilder.build(message: message, board: board, memories: memories,
                                                       taskContext: taskContext, graphContext: graphContext,
                                                       skillIDs: catalog.map(\.id))
        // M1: per-role routing may inject the routed .planning transport; nil
        // keeps the default internal-model completion. Passthrough only — the
        // fallback semantics (catch → .fallback(reason:)) stay in the planner.
        if let complete {
            return await InternalContextPlanner.plan(message: message, context: context, budget: budget, complete: complete)
        }
        return await InternalContextPlanner.plan(message: message, context: context, budget: budget)
    }
    /// Reserve room for every source so a long transcript cannot evict rules or memory.
    static func taskEvidence(history: String, ledger: String, facts: String, rules: String, skills: String) -> String {
        let sources: [(String, String, Int)] = [
            ("Последний диалог", history, 1800), ("Состояние задачи", ledger, 700),
            ("Память", facts, 900), ("Правила проекта", rules, 900), ("Навыки", skills, 1200)
        ]
        return sources.compactMap { title, body, cap in
            guard !body.isEmpty else { return nil }
            let clipped = title == "Последний диалог" ? String(body.suffix(cap)) : String(body.prefix(cap))
            return "\(title):\n\(clipped)" + (body.count > cap ? "\n[сокращено]" : "")
        }.joined(separator: "\n\n")
    }
}
