import Foundation

/// Runs the real context pipeline for a message without sending it, and
/// returns exactly what the model would receive — the payload behind
/// `POST /api/context-preview`. Same pieces as `sendDirectly`: index, memory,
/// ledger-less preview, internal planner, impact pass, system instruction,
/// skills and graph — so a live API check verifies the actual pipeline, not a
/// second implementation of it.
enum ContextPreviewService {

    struct Request {
        let message: String
        let projectPath: String
        let isEnabled: Bool
        let isPlannerEnabled: Bool
        let systemPrompt: String
        let skillsDirectory: URL?
        let isPlanMode: Bool
    }

    /// Thread-safe stage log: the compiler reports from a detached task while
    /// the caller waits for the result.
    final class StageCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [ContextStageLogLogic.Stage] = []

        func append(_ stage: ContextStageLogLogic.Stage) {
            lock.lock()
            storage.append(stage)
            lock.unlock()
        }

        var stages: [ContextStageLogLogic.Stage] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    static func run(_ request: Request) async -> [String: Any] {
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["error": "message is required"]
        }
        let records: [FileIndexRecord] = request.projectPath.isEmpty
            ? []
            : await Task.detached(priority: .utility) {
                ProjectFileIndexStore.load(projectPath: request.projectPath)
            }.value
        var memories: [ProjectMemoryChunk] = []
        if !request.projectPath.isEmpty {
            memories = (try? await Task.detached(priority: .utility) {
                try ProjectMemoryStore.loadChunks(projectPath: request.projectPath)
            }.value) ?? []
        }
        var localPlan: LocalQueryPlanResult?
        var board: ContextBoard?
        if request.isPlannerEnabled, !request.projectPath.isEmpty {
            let built = await Task.detached(priority: .utility) {
                ContextBoardBuilder.build(projectPath: request.projectPath, records: records)
            }.value
            board = built
            localPlan = await TurnContextPlanningService.plan(message: trimmed, board: built, memories: memories,
                                                              records: records, priorTurns: [], ledger: nil)
        }
        var impact: ImpactReport?
        if !request.projectPath.isEmpty {
            let query = {
                let plan = ContextQueryPlanner.plan(for: trimmed)
                return (plan.terms + plan.symbols).joined(separator: " ")
            }()
            impact = await Task.detached(priority: .utility) { () -> ImpactReport? in
                try? ImpactAnalyzer.report(
                    projectPath: request.projectPath,
                    message: trimmed,
                    query: query,
                    records: records,
                    intent: localPlan?.plan?.intent,
                    semanticTerms: (localPlan?.plan?.terms ?? []) + (localPlan?.plan?.symbols ?? []) + (localPlan?.plan?.files ?? [])
                )
            }.value
        }
        let collector = StageCollector()
        let preparation = await SendContextPreparationLogic.prepareAsync(
            message: trimmed,
            records: records,
            projectPath: request.projectPath,
            isEnabled: request.isEnabled,
            memories: memories,
            ledger: nil,
            localPlan: localPlan,
            board: board,
            priorTurns: [],
            isPlanMode: request.isPlanMode,
            systemPrompt: request.systemPrompt,
            skillsDirectory: request.skillsDirectory,
            impact: impact,
            onStage: { collector.append($0) }
        )
        var payload = ContextPreviewLogic.payload(
            message: trimmed,
            preparation: preparation,
            stages: collector.stages,
            systemPrompt: request.systemPrompt
        )
        payload["projectPath"] = request.projectPath
        payload["indexedFiles"] = records.count
        payload["memoryChunks"] = memories.count
        payload["planner"] = localPlan.map { plan -> String in
            switch plan.status {
            case .local(let model): return model
            case .fallback(let reason): return "fallback: \(reason)"
            }
        } ?? "off"
        payload["impactDependents"] = impact?.dependents.count ?? 0
        return payload
    }
}
