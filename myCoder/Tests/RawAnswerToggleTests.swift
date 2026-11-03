import Testing
import Foundation
@testable import myCoder

/// User directive 2026-11-03 (п.3): the raw answer must be reachable by a
/// button next to resend/retry that swaps the rendered message for the raw
/// one. The old leaf-icon button (which turned the message into plain text for
/// selection) is no longer wanted.
@Suite("Кнопка сырого ответа у сообщения")
struct RawAnswerToggleTests {

    @Test("Сырой ответ берётся из событий провода, а не из разметки")
    func rawUsesWireEvents() {
        let raw = TurnPresentation.rawText(events: ["{\"delta\":1}", "[DONE]"], fallback: "rendered")
        #expect(raw == "{\"delta\":1}\n\n[DONE]")
    }

    @Test("Без событий провода показывается текст сообщения")
    func fallsBackToMessageText() {
        #expect(TurnPresentation.rawText(events: nil, fallback: "answer") == "answer")
        #expect(TurnPresentation.rawText(events: [], fallback: "answer") == "answer")
    }

    @Test("Кнопка есть у любого непустого сообщения")
    func toggleAvailableForAnyNonEmptyMessage() {
        #expect(RawAnswerToggleLogic.canToggle(messageText: "ответ", rawEvents: nil))
        #expect(RawAnswerToggleLogic.canToggle(messageText: "", rawEvents: ["x"]))
        #expect(!RawAnswerToggleLogic.canToggle(messageText: "", rawEvents: nil))
    }

    @Test("Иконка и подсказка отражают текущий режим")
    func iconReflectsMode() {
        #expect(RawAnswerToggleLogic.icon(isRaw: false) == "chevron.left.forwardslash.chevron.right")
        #expect(RawAnswerToggleLogic.icon(isRaw: true) == "text.alignleft")
        #expect(RawAnswerToggleLogic.tooltipKey(isRaw: false) == .locRawText)
        #expect(RawAnswerToggleLogic.tooltipKey(isRaw: true) == .locFormatted)
    }

    @Test("Переключение меняет режим и не зависит от выделения текста")
    func toggleFlipsMode() {
        #expect(RawAnswerToggleLogic.toggled(isRaw: false) == true)
        #expect(RawAnswerToggleLogic.toggled(isRaw: true) == false)
    }
}
