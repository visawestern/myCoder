import Foundation
import Testing
@testable import myCoder

/// Чистая логика гидрации сообщений результатами тулов: один раз всё
/// собрать (splitKeys) и применить к частям (apply). Memory-first
/// доказывается тем, что ключи уже лежащие в памяти не попадают в
/// список «нужно качать».
@Suite("Логика гидрации сообщений результатами тулов")
struct ToolResultHydrationLogicTests {

    private func message(withParts parts: [MessagePartContent],
                         meta: [String: ToolResultMeta] = [:]) -> Message {
        Message(id: "m", role: .assistant, content: "", parts: parts, toolResultMeta: meta)
    }

    @Test("splitKeys: ключи из памяти не просят качать с диска")
    func splitKeysMemoryFirst() {
        let keys = ["c1", "c2", "c3"]
        let memory = ["c1": "из памяти", "c3": "тоже из памяти"]
        let split = ToolResultHydrationLogic.splitKeys(keys, memory: memory)
        #expect(split.fromMemory == ["c1": "из памяти", "c3": "тоже из памяти"])
        #expect(split.missing == ["c2"])
    }

    @Test("apply заменяет только части с result == nil по найденным ключам")
    func applyFillsMissingResults() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: "уже есть", callID: "c1"),
            .toolCall(name: "read", args: "{}", result: nil, callID: "c2"),
            .toolCall(name: "read", args: "{}", result: nil, callID: "c3"),
            .text("ответ"),
        ]
        let hydrated = ToolResultHydrationLogic.apply(
            results: ["c2": "пришёл из базы"],
            to: [message(withParts: parts)]
        )
        guard case .toolCall(_, _, let r1, _) = hydrated[0].parts[0] else {
            Issue.record("ожидался toolCall")
            return
        }
        guard case .toolCall(_, _, let r2, _) = hydrated[0].parts[1] else {
            Issue.record("ожидался toolCall")
            return
        }
        guard case .toolCall(_, _, let r3, _) = hydrated[0].parts[2] else {
            Issue.record("ожидался toolCall")
            return
        }
        #expect(r1 == "уже есть")
        #expect(r2 == "пришёл из базы")
        #expect(r3 == nil)
        guard case .text(let text) = hydrated[0].parts[3], text == "ответ" else {
            Issue.record("ожидался текст-часть")
            return
        }
    }

    @Test("apply не трогает сообщения без изменений")
    func applyKeepsUnchangedMessages() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: "ок", callID: "c1"),
        ]
        let original = message(withParts: parts)
        let hydrated = ToolResultHydrationLogic.apply(
            results: ["c1": "другой"],
            to: [original]
        )
        guard case .toolCall(_, _, let r, _) = hydrated[0].parts[0] else {
            Issue.record("ожидался toolCall")
            return
        }
        #expect(r == "ок")
    }

    @Test("keysNeeded собирает только callID с hasStoredResult и без результата")
    func keysNeededCollects() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "read", args: "{}", result: "есть", callID: "c1"),
            .toolCall(name: "read", args: "{}", result: nil, callID: "c2"),
            .toolCall(name: "read", args: "{}", result: nil, callID: "c3"),
        ]
        let meta: [String: ToolResultMeta] = [
            "c2": ToolResultMeta(callID: "c2", hasStoredResult: true, length: 10),
            "c3": ToolResultMeta(callID: "c3", hasStoredResult: false, length: 0),
        ]
        let keys = ToolResultHydrationLogic.keysNeeded(messages: [message(withParts: parts, meta: meta)])
        #expect(keys == ["c2"])
    }
}
