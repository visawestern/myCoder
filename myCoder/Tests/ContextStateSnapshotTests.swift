import Testing
import Foundation
@testable import myCoder

/// `/api/state` reported the selection and the UI, but nothing about the
/// context pipeline: whether point context is on, whether the local planner is
/// on, which model is assigned to internal work, and what stage the assembly is
/// in right now. Without those, "is the context actually being assembled?"
/// cannot be answered over HTTP.
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
}
