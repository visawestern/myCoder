import Foundation
import Testing
@testable import myCoder

/// Once a tool call is parsed and shown as its own spoiler part, the raw
/// ```tool … ``` fence must not remain in the plain answer text — otherwise it
/// is rendered twice (user directive 2026-10-29: "если пошла обработка тула
/// то сразу его переноси из обычного текста в спойлер что бы небыло
/// задвоения").
@Suite("Выноска вызовов инструментов из обычного текста")
struct WebToolFenceStrippingTests {

    @Test("Одиночный фенс тула убирается из текста")
    func stripsSingleToolFence() {
        let text = "Проверю файл.\n\n```tool\nread_file {\"path\": \"a.swift\"}\n```\n\nГотово."
        let result = WebToolProtocolEmulator.strippingToolFences(from: text)
        #expect(!result.contains("```tool"))
        #expect(!result.contains("read_file {\"path\""))
        #expect(result.contains("Проверю файл."))
        #expect(result.contains("Готово."))
    }

    @Test("Несколько фенсов убираются, проза остаётся")
    func stripsMultipleToolFences() {
        let text = """
        ```tool
        list_dir {"path": "."}
        ```
        Промежуточная мысль.
        ```tool
        read_file {"path": "b.swift"}
        ```
        Итог.
        """
        let result = WebToolProtocolEmulator.strippingToolFences(from: text)
        #expect(!result.contains("```tool"))
        #expect(!result.contains("list_dir"))
        #expect(!result.contains("read_file"))
        #expect(result.contains("Промежуточная мысль."))
        #expect(result.contains("Итог."))
    }

    @Test("Не-tool фенсы (python/markdown) остаются нетронутыми")
    func leavesNonToolFences() {
        let text = "Вот код:\n\n```python\nprint(1)\n```"
        let result = WebToolProtocolEmulator.strippingToolFences(from: text)
        #expect(result == text)
    }

    @Test("Без фенсов тула текст не меняется")
    func leavesPlainTextUntouched() {
        let text = "Просто ответ без инструментов."
        #expect(WebToolProtocolEmulator.strippingToolFences(from: text) == text)
    }

    @Test("Если в ответе только фенс тула, остаётся пусто")
    func onlyToolFenceYieldsEmpty() {
        let text = "```tool\nwrite_file {\"path\": \"x\"}\n```"
        let result = WebToolProtocolEmulator.strippingToolFences(from: text)
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("appendAnswer не дублирует вынос тула в обычном тексте")
    func appendAnswerStripsFenceWhenToolCallsExist() {
        let timeline: [MessagePartContent] = [
            .toolCall(name: "read_file", args: "{\"path\":\"a\"}", result: "ok", callID: "c1")
        ]
        let answer = "```tool\nread_file {\"path\": \"a\"}\n```\nОтвет."
        let parts = AssistantTurnPartsLogic.directTimelineParts(timeline: timeline, answer: answer)
        let textPart = parts.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
        #expect(textPart == ["Ответ."])
    }
}
