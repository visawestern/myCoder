import Foundation
import Testing
@testable import myCoder

/// The direct tool loops persisted reasoning and tool parts but kept
/// the answer only in `content`, which the row renders above the parts — a
/// finished reply showed its reasoning block at the very end (user report
/// 2026-10-29). These tests pin the display order.
@Suite("Порядок блоков ответа ассистента")
struct AssistantTurnPartsLogicTests {

    private func kinds(_ parts: [MessagePartContent]) -> [String] {
        parts.map { part in
            switch part {
            case .text: return "text"
            case .reasoning: return "reasoning"
            case .toolCall(let name, _, _, _): return "tool:\(name)"
            case .stepStart: return "stepStart"
            case .stepFinish: return "stepFinish"
            case .compiledContext: return "context"
            case .image: return "image"
            case .routeInfo: return "route"
            }
        }
    }

    @Test("Прямой маршрут: рассуждение сверху, тулы по порядку, ответ в конце")
    func directPartsKeepChronologicalOrder() {
        let parts = AssistantTurnPartsLogic.directParts(
            reasoning: "думаю",
            toolParts: [
                .toolCall(name: "read_file", args: "{}", result: "ok", callID: "c1"),
                .toolCall(name: "edit", args: "{}", result: "ok", callID: "c2")
            ],
            answer: "готово"
        )
        #expect(kinds(parts) == ["reasoning", "tool:read_file", "tool:edit", "text"])
    }

    @Test("Прямой маршрут без рассуждения: сначала вызовы, затем ответ")
    func directPartsWithoutReasoning() {
        let parts = AssistantTurnPartsLogic.directParts(
            reasoning: nil,
            toolParts: [.toolCall(name: "read_file", args: "{}", result: nil, callID: "c1")],
            answer: "ответ"
        )
        #expect(kinds(parts) == ["tool:read_file", "text"])
    }

    @Test("Ответ не дублируется, если текстовая часть уже есть")
    func answerIsNotDuplicated() {
        let parts = AssistantTurnPartsLogic.directTimelineParts(
            timeline: [.text("итог")],
            answer: "итог"
        )
        #expect(kinds(parts) == ["text"])
    }

    @Test("Старые сообщения без text-части не показывают ответ над рассуждением")
    func legacyMessageGetsTextPartAtTheEnd() {
        let parts = MessageRowPartsLogic.displayParts(
            parts: [.reasoning("думаю")],
            content: "старый ответ"
        )
        #expect(kinds(parts) == ["reasoning", "text"])
    }

    @Test("Существующая text-часть не дублируется фолбэком")
    func existingTextPartIsKept() {
        let original: [MessagePartContent] = [.reasoning("думаю"), .text("ответ")]
        let parts = MessageRowPartsLogic.displayParts(parts: original, content: "ответ")
        #expect(kinds(parts) == ["reasoning", "text"])
    }

    @Test("Пустой контент не добавляет пустую text-часть")
    func emptyContentAddsNothing() {
        let parts = MessageRowPartsLogic.displayParts(parts: [.reasoning("думаю")], content: "")
        #expect(kinds(parts) == ["reasoning"])
    }
}
