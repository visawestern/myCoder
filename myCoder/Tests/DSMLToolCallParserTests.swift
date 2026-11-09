import Testing
import Foundation
@testable import myCoder

/// Поддержка XML-подобного протокола вызовов инструментов «DSML», который
/// часть моделей (DeepSeek V4.1 Flash / MiMo-style агенты) эмитят вместо
/// наших ```tool-блоков. Live-дефект 2026-11-09: чат завис на
/// `<｜DSML｜ invoke …>` — вызов не исполнялся, ответ показывался как текст.
@Suite("Инструменты — DSML формат вызовов")
struct DSMLToolCallParserTests {

    private func args(_ call: WebToolCall, _ key: String) -> String? {
        call.arguments[key]
    }

    @Test("Полный блок DSML из чата парсится в вызовы с аргументами")
    func parsesFullDSMLBlock() {
        // Дословно то, что модель прислала в живом чате (полнойширинные |).
        let text = """
        <｜DSML｜ calls>
        <｜DSML｜ invoke name="list_dir">
        <｜DSML｜ parameter name="path" string="true">.</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        <｜DSML｜ invoke name="glob">
        <｜DSML｜ parameter name="pattern" string="true">**/ModelGroupingLogic.swift</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        </｜DSML｜ calls>
        """
        let calls = DSMLToolCallParser.parseCalls(from: text)
        #expect(calls.count == 2)
        #expect(calls[0].name == "list_dir")
        #expect(args(calls[0], "path") == ".")
        #expect(calls[1].name == "glob")
        #expect(args(calls[1], "pattern") == "**/ModelGroupingLogic.swift")
    }

    @Test("Обычные | и ASCII-теги тоже понимаются")
    func parsesAsciiVariant() {
        let text = """
        <|DSML| invoke name="grep">
        <|DSML| parameter name="pattern" string="true">needle</|DSML| parameter>
        </|DSML| invoke>
        """
        let calls = DSMLToolCallParser.parseCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "grep")
        #expect(args(calls[0], "pattern") == "needle")
    }

    @Test("Invoke без обёртки calls парсится")
    func parsesBareInvoke() {
        let text = """
        Сначала проверю структуру.
        <｜DSML｜ invoke name="list_dir">
        <｜DSML｜ parameter name="path" string="true">src</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        """
        let calls = DSMLToolCallParser.parseCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "list_dir")
        #expect(args(calls[0], "path") == "src")
    }

    @Test("Значение с кавычками и спецсимволами не ломает парсер")
    func parsesValuesWithSpecialChars() {
        let text = """
        <｜DSML｜ calls>
        <｜DSML｜ invoke name="glob">
        <｜DSML｜ parameter name="pattern" string="true">src/*.swift</｜DSML｜ parameter>
        <｜DSML｜ parameter name="limit" string="true">3</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        <｜DSML｜ invoke name="grep">
        <｜DSML｜ parameter name="pattern" string="true">a &amp; b</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        </｜DSML｜ calls>
        """
        let calls = DSMLToolCallParser.parseCalls(from: text)
        #expect(calls.count == 2)
        #expect(calls[0].name == "glob")
        #expect(args(calls[0], "pattern") == "src/*.swift")
        #expect(args(calls[0], "limit") == "3")
        #expect(calls[1].name == "grep")
        #expect(args(calls[1], "pattern") == "a & b")
    }

    @Test("Не-DSML теги и проза игнорируются")
    func ignoresForeignTags() {
        let text = """
        <div>обычный html</div>
        <greeting>hello</greeting>
        А тут просто текст с <tool_call>execute_command<arg_key>command</arg_key></tool_call>.
        """
        #expect(DSMLToolCallParser.parseCalls(from: text).isEmpty)
    }

    @Test("Неизвестное имя инструмента не создаёт вызов")
    func unknownToolNameSkipped() {
        let text = """
        <｜DSML｜ invoke name="no_such_tool">
        <｜DSML｜ parameter name="path" string="true">.</｜DSML｜ parameter>
        </｜DSML｜ invoke>
        """
        #expect(DSMLToolCallParser.parseCalls(from: text).isEmpty)
    }

    @Test("Пустой текст и текст без DSML не дают вызовов")
    func emptyTextYieldsNoCalls() {
        #expect(DSMLToolCallParser.parseCalls(from: "").isEmpty)
        #expect(DSMLToolCallParser.parseCalls(from: "просто ответ без инструментов").isEmpty)
    }
}
