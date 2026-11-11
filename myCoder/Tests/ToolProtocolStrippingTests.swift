import Testing
import Foundation
@testable import myCoder

/// Живой дефект 2026-11-09: DSML-вызовы исполнялись (tool-call части с
/// результатами были), но сырой `<｜DSML｜ calls>…` оставался в тексте ответа
/// вместе с «⏳ Running tools...». Вызов должен жить в tool-call части, а не
/// в пузыре.
@MainActor
@Suite("Чистка протокола вызовов из текста")
struct ToolProtocolStrippingTests {

    private let dsmlBlock = """
    <｜DSML｜ calls>
    <｜DSML｜ invoke name="read_file">
    <｜DSML｜ parameter name="path" string="true">a.swift</｜DSML｜ parameter>
    </｜DSML｜ invoke>
    <｜DSML｜ invoke name="grep">
    <｜DSML｜ parameter name="pattern" string="true">foo</｜DSML｜ parameter>
    </｜DSML｜ invoke>
    </｜DSML｜ calls>
    """

    @Test("DSML-блок удаляется, проза остаётся")
    func stripsDSMLBlock() {
        let text = "Пути не сработали — пробую полные пути.\n\n\(dsmlBlock)"
        let visible = ToolProtocolStripping.visibleText(from: text)
        #expect(visible == "Пути не сработали — пробую полные пути.")
        #expect(!visible.contains("DSML"))
    }

    @Test("ASCII-скобки |DSML| тоже удаляются")
    func stripsASCIIDSML() {
        let text = """
        Ответ.
        <|DSML| invoke name="list_dir">
        <|DSML| parameter name="path">.</|DSML| parameter>
        </|DSML| invoke>
        """
        #expect(ToolProtocolStripping.visibleText(from: text) == "Ответ.")
    }

    @Test("Несколько invoke в одном блоке удаляются все")
    func stripsAllInvokes() {
        let visible = ToolProtocolStripping.visibleText(from: dsmlBlock)
        #expect(visible.isEmpty)
        #expect(!visible.contains("invoke"))
    }

    @Test("```tool fence удаляется")
    func stripsToolFence() {
        let text = "Сейчас прочитаю.\n```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"a\"}}\n```"
        #expect(ToolProtocolStripping.visibleText(from: text) == "Сейчас прочитаю.")
    }

    @Test("Anthropic function_calls удаляется")
    func stripsAnthropicCalls() {
        let text = """
        Проверяю.
        <function_calls>
        <invoke name="read_file"><parameter name="path">a.swift</parameter></invoke>
        </function_calls>
        """
        #expect(ToolProtocolStripping.visibleText(from: text) == "Проверяю.")
    }

    @Test("Одиночный self-closing function_call удаляется")
    func stripsSelfClosingFunctionCall() {
        let text = #"Готово. <function_call name="grep" arguments="{}" />"#
        #expect(ToolProtocolStripping.visibleText(from: text) == "Готово.")
    }

    @Test("Статус «⏳ Running tools...» исчезает")
    func stripsRunningToolsStatus() {
        let text = "Читаю файлы.\n\n⏳ Running tools..."
        #expect(ToolProtocolStripping.visibleText(from: text) == "Читаю файлы.")
    }

    @Test("Текст без протокола не меняется (кроме trim)")
    func keepsPlainText() {
        let text = "  Обычный ответ модели.\n\nВторой абзац.  "
        #expect(ToolProtocolStripping.visibleText(from: text) == "Обычный ответ модели.\n\nВторой абзац.")
    }

    @Test("containsToolProtocol отличает вызов от обычного текста")
    func detectsProtocol() {
        #expect(ToolProtocolStripping.containsToolProtocol(dsmlBlock))
        #expect(!ToolProtocolStripping.containsToolProtocol("просто ответ"))
    }

    @Test("displayParts: fallback-контент попадает в поток очищенным")
    func displayPartsSanitizesFallback() {
        let parts: [MessagePartContent] = [
            .toolCall(name: "read_file", args: "path=a.swift", result: "ok", callID: nil)
        ]
        let content = "Сейчас прочитаю.\n\n\(dsmlBlock)\n\n⏳ Running tools..."
        let display = MessageRowPartsLogic.displayParts(parts: parts, content: content)
        let texts = display.compactMap { part -> String? in
            if case .text(let value) = part { return value }
            return nil
        }
        #expect(texts == ["Сейчас прочитаю."])
    }

    @Test("appendAnswer: DSML не дублирует tool-call и не остаётся в ответе")
    func appendAnswerStripsProtocol() {
        let timeline: [MessagePartContent] = [
            .toolCall(name: "read_file", args: "path=a.swift", result: "ok", callID: nil)
        ]
        let parts = AssistantTurnPartsLogic.directTimelineParts(
            timeline: timeline,
            answer: "Прочитал.\n\n\(dsmlBlock)"
        )
        let texts = parts.compactMap { part -> String? in
            if case .text(let value) = part { return value }
            return nil
        }
        #expect(texts == ["Прочитал."])
        #expect(parts.filter { if case .toolCall = $0 { return true }; return false }.count == 1)
    }

    @Test("toolCallCount считает вызовы в сообщении")
    func countsToolCalls() {
        let message = Message(
            role: .assistant,
            content: "ответ",
            parts: [
                .reasoning("думаю"),
                .toolCall(name: "read_file", args: "path=a", result: "ok", callID: "1"),
                .toolCall(name: "grep", args: "pattern=b", result: "ok", callID: "2"),
                .text("ответ")
            ]
        )
        #expect(message.toolCallCount == 2)
    }

    @Test("formatToolResults собирает несколько результатов в один блок")
    func formatsSingleResultsBlock() {
        let block = WebToolProtocolEmulator.formatToolResults([
            (name: "read_file", result: "A"),
            (name: "grep", result: "B")
        ])
        #expect(block.components(separatedBy: "```tool_result").count == 3)
        #expect(block.contains("\"name\": \"read_file\""))
        #expect(block.contains("\"name\": \"grep\""))
    }
}
