import Foundation

/// Контекст запуска полного цикла отката: чистые данные планирования и
/// инъекции безопасности (снапшоты, корзина, пометка undo).
struct RollbackCoordinatorContext {
    let targetMessageID: String
    let messages: [RollbackMessageRef]
    let undoEntries: [RollbackUndoEntryRef]
    let irreversibleActions: [IrreversibleAgentAction]
    let snapshotRestoring: RollbackSnapshotRestoring
    let trashStoring: RollbackTrashStoring
    let undoMarking: RollbackUndoMarking
}

/// Оркестратор полного цикла отката:
/// 1. детерминированный план (`RollbackPlanLogic`);
/// 2. если доступна внутренняя модель — аудитор диалога
///    (`RollbackPromptBuilder`), его вердикт дополняет отчёт, но НЕ
///    отменяет безопасный план; при недоступности — честный fallback;
/// 3. безопасное исполнение (`RollbackExecutor`): корзина → restore →
///    пометка undo;
/// 4. формирование данных оранжевого чипа отката.
enum RollbackCoordinator {

    typealias Auditor = (_ system: String, _ user: String) async throws -> String

    static func run(context: RollbackCoordinatorContext,
                    auditor: Auditor? = nil) async -> RollbackChipData {
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: context.targetMessageID,
            messages: context.messages,
            undoEntries: context.undoEntries,
            irreversibleActions: context.irreversibleActions
        )

        let auditorStage: RollbackStage?
        if let auditor {
            auditorStage = await runAuditor(auditor, context: context)
        } else {
            auditorStage = RollbackStage(
                title: "Аудитор",
                success: true,
                detail: "Внутренняя модель не подключена — использован детерминированный план."
            )
        }

        let report = await RollbackExecutor.execute(
            plan: plan,
            restore: context.snapshotRestoring,
            trash: context.trashStoring,
            markUsed: context.undoMarking
        )

        var stages = report.stages
        if let auditorStage {
            stages.insert(auditorStage, at: 0)
        }

        let summary = makeSummary(plan: plan, diffsCount: report.diffs.count, error: report.error)
        let fullReport = RollbackReport(plan: plan, stages: stages, diffs: report.diffs, error: report.error)
        return RollbackChipData(createdAt: Date(), full: plan.full, summary: summary, report: fullReport)
    }

    private static func runAuditor(_ auditor: Auditor,
                                   context: RollbackCoordinatorContext) async -> RollbackStage? {
        let system = RollbackPromptBuilder.systemPrompt()
        let user = RollbackPromptBuilder.userPrompt(
            targetMessageID: context.targetMessageID,
            messages: context.messages,
            irreversibleActions: context.irreversibleActions
        )
        do {
            let answer = try await auditor(system, user)
            guard let verdict = RollbackPromptBuilder.parseVerdict(answer) else {
                return RollbackStage(title: "Аудитор", success: false,
                                     detail: "Ответ аудитора не распознан — использован план.")
            }
            let detail = verdict.canRollback
                ? "Аудитор подтвердил: откат возможен."
                : "Аудитор предупредил о необратимом: \(verdict.irreversible.joined(separator: ", "))."
            return RollbackStage(title: "Аудитор", success: verdict.canRollback, detail: detail)
        } catch {
            return RollbackStage(title: "Аудитор", success: false,
                                 detail: "Аудитор недоступен (\(error.localizedDescription)) — использован план.")
        }
    }

    private static func makeSummary(plan: RollbackPlan, diffsCount: Int, error: String?) -> String {
        if let error {
            return "Ошибка: \(error)"
        }
        let outcome = plan.full ? "полный" : "частичный"
        let files = diffsCount == 1 ? "1 файл" : "\(diffsCount) файла(ов)"
        if plan.full {
            return "Откат \(outcome): восстановлено \(files)."
        }
        return "Откат \(outcome) до \(plan.visibilityCutMessageID ?? "границы") — \(plan.stopReason ?? "")"
    }
}
