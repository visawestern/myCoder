import Testing
import Foundation
@testable import myCoder

/// `/api/state` reported the selection and the UI, but nothing about the
/// context pipeline: whether point context is on, whether the local planner is
/// on, which model is assigned to internal work, and what stage the assembly is
/// in right now. Without those, "is the context actually being assembled?"
/// cannot be answered over HTTP.
@MainActor
@Suite("Снапшот /api/state показывает конвейер контекста")
struct ContextStateSnapshotTests {

    @Test("Блок context несёт флаги, внутреннюю модель и стадию")
    func contextBlockCarriesPipelineState() {
        let block = ContextStateSnapshotLogic.block(
            isPointContextEnabled: true,
            isLocalQueryPlannerEnabled: false,
            isCompiling: true,
            stageLine: "План: разбираю запрос",
            internalModels: [InternalModelRef(providerID: "p1", modelID: "m1")],
            indexedFileCount: 412
        )
        #expect(block["isPointContextEnabled"] as? Bool == true)
        #expect(block["isLocalQueryPlannerEnabled"] as? Bool == false)
        #expect(block["isCompiling"] as? Bool == true)
        #expect(block["stage"] as? String == "План: разбираю запрос")
        #expect(block["indexedFileCount"] as? Int == 412)
        let models = block["internalModels"] as? [[String: String]]
        #expect(models?.count == 1)
        #expect(models?.first?["providerID"] == "p1")
        #expect(models?.first?["modelID"] == "m1")
    }

    @Test("Пустая стадия не превращается в null-строку")
    func emptyStageIsEmptyString() {
        let block = ContextStateSnapshotLogic.block(
            isPointContextEnabled: false,
            isLocalQueryPlannerEnabled: false,
            isCompiling: false,
            stageLine: "",
            internalModels: [],
            indexedFileCount: 0
        )
        #expect(block["stage"] as? String == "")
        #expect((block["internalModels"] as? [[String: String]])?.isEmpty == true)
    }

    @Test("Без назначенной внутренней модели список пуст, а не падает")
    func noInternalModelIsHonest() {
        let block = ContextStateSnapshotLogic.block(
            isPointContextEnabled: true,
            isLocalQueryPlannerEnabled: true,
            isCompiling: false,
            stageLine: "",
            internalModels: [],
            indexedFileCount: 0
        )
        #expect((block["internalModels"] as? [[String: String]])?.isEmpty == true)
    }

    @Test("Журнал сборки виден по HTTP со всеми тремя частями действия")
    func assemblyLogIsExposed() {
        var log = ContextAssemblyLogLogic.begin(message: "q", projectRoot: "/tmp/p")
        log = ContextAssemblyLogLogic.start(
            key: ContextAssemblyLogLogic.indexKey,
            title: "Индекс проекта",
            request: "Корень проекта: /tmp/p",
            processing: "Читаю индекс",
            in: log
        )
        log = ContextAssemblyLogLogic.finish(
            key: ContextAssemblyLogLogic.indexKey,
            result: "Файлов в индексе: 42",
            status: .done,
            in: log
        )
        let block = ContextStateSnapshotLogic.block(
            isPointContextEnabled: true,
            isLocalQueryPlannerEnabled: false,
            isCompiling: false,
            stageLine: "",
            internalModels: [],
            indexedFileCount: 42,
            log: log
        )
        let entries = block["assemblyLog"] as? [[String: Any]]
        #expect(entries?.count == 2)
        let indexEntry = entries?.first { $0["key"] as? String == ContextAssemblyLogLogic.indexKey }
        #expect(indexEntry?["request"] as? String == "Корень проекта: /tmp/p")
        #expect(indexEntry?["processing"] as? String == "Читаю индекс")
        #expect(indexEntry?["result"] as? String == "Файлов в индексе: 42")
        #expect(indexEntry?["status"] as? String == "done")
    }

    @Test("Сжатие при смене модели видно по HTTP со всеми действиями")
    func modelSwitchCompactionIsExposed() {
        var notice = ModelSwitchCompactionNotice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            phase: .compacted,
            alternatives: [
                ModelSwitchCompactionLogic.Candidate(
                    id: "huge",
                    window: 1_000_000,
                    providerID: "p2",
                    providerName: "Two"
                )
            ],
            summaryMessageID: "summary",
            noticeMessageID: "note",
            error: nil,
            sessionID: "s1"
        )
        let block = ModelSwitchCompactionSnapshotLogic.block(notice)
        #expect(block["active"] as? Bool == true)
        #expect(block["phase"] as? String == "compacted")
        #expect(block["previousModel"] as? String == "big")
        #expect(block["newModel"] as? String == "small")
        #expect(block["usedTokens"] as? Int == 120_000)
        #expect(block["limitTokens"] as? Int == 64_000)
        #expect((block["alternatives"] as? [[String: Any]])?.count == 1)
        let alternative = (block["alternatives"] as? [[String: Any]])?.first
        #expect(alternative?["modelID"] as? String == "huge")
        #expect(alternative?["providerID"] as? String == "p2")
        #expect(alternative?["providerName"] as? String == "Two")
        #expect(alternative?["window"] as? Int == 1_000_000)
        #expect(block["canRollback"] as? Bool == true)
        #expect(block["canStop"] as? Bool == false)
        #expect(block["canRetry"] as? Bool == false)

        notice.phase = .rolledBack
        notice.summaryMessageID = nil
        notice.noticeMessageID = nil
        let rolledBack = ModelSwitchCompactionSnapshotLogic.block(notice)
        #expect(rolledBack["phase"] as? String == "rolledBack")
        #expect(rolledBack["canRetry"] as? Bool == true)
        #expect(rolledBack["canRollback"] as? Bool == false)

        let empty = ModelSwitchCompactionSnapshotLogic.block(nil)
        #expect(empty["active"] as? Bool == false)
        #expect(empty["phase"] == nil)
    }
}
