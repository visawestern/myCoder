import Testing
import Foundation
@testable import myCoder

/// Исполнение отката через фейковые инъекции: корзина, восстановление из
/// снапшота, пометка undo-записей. Проверяем безопасность (копия ДО
/// восстановления), стадии и диффы.
@MainActor
@Suite("Откат — исполнение")
struct RollbackExecutorTests {

    // MARK: - Фейки

    private final class FakeRestorer: RollbackSnapshotRestoring {
        var restored: [String] = []
        var failingSnapshotIDs: Set<String> = []
        func restoreFromSnapshot(snapshotId: String) throws {
            if failingSnapshotIDs.contains(snapshotId) {
                throw NSError(domain: "test", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "снапшот повреждён"])
            }
            restored.append(snapshotId)
        }
    }

    private final class FakeTrash: RollbackTrashStoring {
        var stored: [(path: String, scope: String)] = []
        func storeCopy(ofFileAt path: String, scope: String) throws -> String? {
            stored.append((path, scope))
            return path + ".trash"
        }
    }

    private final class FakeMarkUsed: RollbackUndoMarking {
        var marked: [String] = []
        func markUndoEntryUsed(id: String) throws {
            marked.append(id)
        }
    }

    private func plan(steps: [RollbackStep], full: Bool = true) -> RollbackPlan {
        RollbackPlan(targetMessageID: "q1", full: full, steps: steps,
                     visibilityCutMessageID: "q1", stopReason: nil, promptRestore: nil)
    }

    private func doneStep(_ id: String, snapshot: String, path: String) -> RollbackStep {
        RollbackStep(entryID: id, snapshotID: snapshot, path: path,
                     actionType: "edit_file", status: .done, reason: nil)
    }

    // MARK: - Тесты

    @Test("Успешный откат: корзина перед восстановлением, стадии и диффы")
    func successfulExecuteStagesAndDiffs() async {
        let restorer = FakeRestorer()
        let trash = FakeTrash()
        let marker = FakeMarkUsed()
        let steps = [doneStep("u1", snapshot: "s1", path: "/tmp/a.swift"),
                     doneStep("u2", snapshot: "s2", path: "/tmp/b.swift")]
        let report = await RollbackExecutor.execute(
            plan: plan(steps: steps),
            restore: restorer,
            trash: trash,
            markUsed: marker
        )

        // Корзина получила копии ОБОИХ файлов до восстановления.
        #expect(trash.stored.count == 2)
        #expect(trash.stored.allSatisfy { $0.scope == "rollback" })
        // Оба снапшота восстановлены, обе записи помечены.
        #expect(restorer.restored == ["s1", "s2"])
        #expect(marker.marked == ["u1", "u2"])
        // Диффы на каждый файл.
        #expect(report.diffs.count == 2)
        #expect(report.diffs[0].path == "/tmp/a.swift")
        // Стадия «Итог» есть и успешна.
        #expect(report.stages.last?.success == true)
        #expect(report.error == nil)
    }

    @Test("Ошибка восстановления → стадия failure и error в отчёте, остальные шаги продолжаются")
    func failedStepReportsErrorAndContinues() async {
        let restorer = FakeRestorer()
        restorer.failingSnapshotIDs = ["s1"]
        let trash = FakeTrash()
        let marker = FakeMarkUsed()
        let steps = [doneStep("u1", snapshot: "s1", path: "/tmp/a.swift"),
                     doneStep("u2", snapshot: "s2", path: "/tmp/b.swift")]
        let report = await RollbackExecutor.execute(
            plan: plan(steps: steps),
            restore: restorer,
            trash: trash,
            markUsed: marker
        )

        #expect(report.error != nil)
        #expect(report.stages.contains { !$0.success })
        // Второй шаг всё равно выполнен.
        #expect(restorer.restored == ["s2"])
        #expect(marker.marked == ["u2"])
    }

    @Test("Пустой план → итог без шагов, без ошибок")
    func emptyPlanExecutesCleanly() async {
        let report = await RollbackExecutor.execute(
            plan: plan(steps: []),
            restore: FakeRestorer(),
            trash: FakeTrash(),
            markUsed: FakeMarkUsed()
        )
        #expect(report.error == nil)
        #expect(report.diffs.isEmpty)
        #expect(report.stages.last?.success == true)
    }
}
