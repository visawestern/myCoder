import Foundation

/// Протокол восстановления файла из снапшота (реальные реализации —
/// ProjectSnapshotManager / FileSnapshotManager).
protocol RollbackSnapshotRestoring {
    func restoreFromSnapshot(snapshotId: String) throws
}

/// Протокол корзины: сохранить копию файла перед перезаписью, чтобы откат
/// никогда не уничтожал данные насовсем (директива «удалять только в
/// корзину»).
protocol RollbackTrashStoring {
    /// Вернуть путь сохранённой копии или nil, если файла не было.
    func storeCopy(ofFileAt path: String, scope: String) throws -> String?
}

/// Протокол пометки undo-записи использованной (чтобы повторный откат того
/// же изменения был невозможен).
protocol RollbackUndoMarking {
    func markUndoEntryUsed(id: String) throws
}

/// Исполнение плана отката. Максимально безопасно:
/// 1. перед восстановлением файла его ТЕКУЩЕЕ состояние сохраняется в
///    корзину (копия, не удаление);
/// 2. файл восстанавливается из снапшота;
/// 3. undo-запись помечается использованной;
/// 4. каждый шаг формирует стадию отчёта и дифф (до/после).
enum RollbackExecutor {

    static func execute(
        plan: RollbackPlan,
        restore: RollbackSnapshotRestoring,
        trash: RollbackTrashStoring,
        markUsed: RollbackUndoMarking
    ) async -> RollbackReport {
        var stages: [RollbackStage] = []
        var diffs: [RollbackFileDiff] = []
        var executeError: String?

        let doneSteps = plan.steps.filter { $0.status == .done }
        if !doneSteps.isEmpty {
            stages.append(RollbackStage(
                title: "Корзина",
                success: true,
                detail: "Текущие копии файлов сохранены перед откатом: \(doneSteps.count)"
            ))
        }

        for step in doneSteps {
            guard let snapshotID = step.snapshotID else { continue }
            do {
                // 1. Корзина: копия текущего состояния ДО восстановления.
                var beforeText = ""
                _ = try trash.storeCopy(ofFileAt: step.path, scope: "rollback")
                beforeText = (try? String(contentsOfFile: step.path, encoding: .utf8)) ?? ""

                // 2. Восстановление из снапшота.
                try restore.restoreFromSnapshot(snapshotId: snapshotID)

                // 3. Пометка использованной.
                if let entryID = step.entryID {
                    try markUsed.markUndoEntryUsed(id: entryID)
                }

                let afterText = (try? String(contentsOfFile: step.path, encoding: .utf8)) ?? ""
                diffs.append(RollbackFileDiff(path: step.path, before: beforeText, after: afterText))
                stages.append(RollbackStage(
                    title: "Восстановлен \(step.path)",
                    success: true,
                    detail: "действие: \(step.actionType)"
                ))
            } catch {
                let message = error.localizedDescription
                executeError = executeError ?? message
                stages.append(RollbackStage(
                    title: "Не удалось откатить \(step.path)",
                    success: false,
                    detail: message
                ))
            }
        }

        if executeError != nil {
            stages.append(RollbackStage(
                title: "Откат прерван ошибкой",
                success: false,
                detail: executeError ?? ""
            ))
        } else {
            let outcome = plan.full ? "полный" : "частичный"
            stages.append(RollbackStage(
                title: "Итог",
                success: true,
                detail: "Откат \(outcome). Файлов восстановлено: \(diffs.count)."
            ))
        }

        return RollbackReport(
            plan: plan,
            stages: stages,
            diffs: diffs,
            error: executeError
        )
    }
}
