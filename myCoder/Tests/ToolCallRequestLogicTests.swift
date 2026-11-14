import Foundation
import Testing
@testable import myCoder

/// Чистая логика ленивой загрузки результатов тулов. Различает три
/// состояния шага: результат уже в памяти (`result != nil`), результат
/// есть в хранилище, но ещё не загружен (`hasStoredResult == true`,
/// `result == nil`) и результата нет вовсе.
@Suite("Логика ленивой загрузки результатов тулов (ToolCallRequestLogic)")
struct ToolCallRequestLogicTests {

    private func step(
        _ id: String,
        result: String?,
        hasStoredResult: Bool = false
    ) -> ToolCallInspectorStep {
        ToolCallInspectorStep(
            id: id,
            name: "read_file",
            args: "{}",
            result: result,
            hasStoredResult: hasStoredResult
        )
    }

    @Test("keysToLoad возвращает только шаги с хранимым, но не загруженным результатом")
    func keysToLoad() {
        let steps = [
            step("a", result: "в памяти"),
            step("b", result: nil, hasStoredResult: true),
            step("c", result: nil),
            step("d", result: nil, hasStoredResult: true),
        ]
        #expect(ToolCallRequestLogic.keysToLoad(steps) == ["b", "d"])
    }

    @Test("keysToLoad пуст, когда всё уже в памяти или результата нет")
    func keysToLoadEmpty() {
        let steps = [
            step("a", result: "ок"),
            step("b", result: nil),
        ]
        #expect(ToolCallRequestLogic.keysToLoad(steps).isEmpty)
    }

    @Test("merge подставляет результаты по id и не трогает уже загруженные")
    func mergeSubstitutesByID() {
        let loaded = [
            ToolCallInspectorStep(id: "a", name: "read", args: "{}", result: "старый"),
            ToolCallInspectorStep(id: "b", name: "read", args: "{}", result: nil, hasStoredResult: true),
        ]
        let merged = ToolCallRequestLogic.merge(
            results: ["a": "новый", "b": "из базы", "missing": "нет шага"],
            into: loaded
        )
        #expect(merged[0].result == "старый")
        #expect(merged[1].result == "из базы")
        #expect(merged[1].hasStoredResult)
    }

    @Test("displayResult предпочитает результат шага, затем подгруженный")
    func displayResultPreferStep() {
        let step = ToolCallInspectorStep(
            id: "x", name: "read", args: "{}",
            result: "в памяти", hasStoredResult: true
        )
        #expect(ToolCallRequestLogic.displayResult(for: step, results: ["x": "по подмене"]) == "в памяти")
        let pending = ToolCallInspectorStep(
            id: "y", name: "read", args: "{}",
            result: nil, hasStoredResult: true
        )
        #expect(ToolCallRequestLogic.displayResult(for: pending, results: ["y": "подгружен"]) == "подгружен")
    }

    @Test("isPending: результат ожидает загрузки")
    func pendingState() {
        let pending = ToolCallInspectorStep(
            id: "y", name: "read", args: "{}",
            result: nil, hasStoredResult: true
        )
        #expect(ToolCallRequestLogic.isPending(pending, results: [:]))
        #expect(!ToolCallRequestLogic.isPending(pending, results: ["y": "готово"]))
    }

    @Test("isUnavailable: результата нет ни в памяти, ни в хранилище")
    func unavailableState() {
        let unavailable = ToolCallInspectorStep(
            id: "z", name: "read", args: "{}",
            result: nil, hasStoredResult: false
        )
        #expect(ToolCallRequestLogic.isUnavailable(unavailable, results: [:]))
        #expect(!ToolCallRequestLogic.isUnavailable(unavailable, results: ["z": "нашёлся"]))
        #expect(!ToolCallRequestLogic.isUnavailable(
            ToolCallInspectorStep(id: "q", name: "read", args: "{}", result: "ок"),
            results: [:]
        ))
    }
}
