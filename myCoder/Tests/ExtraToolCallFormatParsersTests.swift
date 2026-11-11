import Testing
import Foundation
@testable import myCoder

/// Сюрпризы форматов вызовов инструментов, которые модели эмитят в тексте
/// ответа помимо наших ```tool-блоков. Каждый формат покрыт отдельным тестом,
/// чтобы ни один из них снова не «завис» неисполненным (live-дефект
/// 2026-11-09: DSML-блок в чате не исполнялся).
@MainActor
@Suite("Инструменты — дополнительные форматы вызовов")
struct ExtraToolCallFormatParsersTests {

    private func args(_ call: WebToolCall, _ key: String) -> String? {
        call.arguments[key]
    }

    // MARK: - Anthropic function_calls / invoke / parameter

    @Test("Anthropic function_calls с invoke/parameter парсится")
    func parsesAnthropicFunctionCalls() {
        let text = """
        <function_calls>
        <invoke name="read_file">
        <parameter name="file_path">src/Main.swift</parameter>
        </invoke>
        <invoke name="grep">
        <parameter name="pattern">func main</parameter>
        </invoke>
        </function_calls>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 2)
        #expect(calls[0].name == "read_file")
        #expect(args(calls[0], "file_path") == "src/Main.swift")
        #expect(calls[1].name == "grep")
        #expect(args(calls[1], "pattern") == "func main")
    }

    @Test("Одиночный invoke без обёртки function_calls парсится")
    func parsesBareInvoke() {
        let text = """
        <invoke name="list_dir">
        <parameter name="path">.</parameter>
        </invoke>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "list_dir")
        #expect(args(calls[0], "path") == ".")
    }

    // MARK: - Anthropic tool_use / input

    @Test("Anthropic tool_use с input-JSON парсится")
    func parsesToolUseWithJsonInput() {
        let text = """
        <tool_use id="call_1" name="edit_file">
        <input>{"file_path": "src/Main.swift", "old_string": "a", "new_string": "b"}</input>
        </tool_use>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "edit_file")
        #expect(args(calls[0], "file_path") == "src/Main.swift")
        #expect(args(calls[0], "old_string") == "a")
        #expect(args(calls[0], "new_string") == "b")
    }

    @Test("Anthropic tool_use с input k=v парсится")
    func parsesToolUseWithKVInput() {
        let text = """
        <tool_use name="run_command">
        <input>command="ls -la"</input>
        </tool_use>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "run_command")
        #expect(args(calls[0], "command") == "ls -la")
    }

    // MARK: - <function_call name=... arguments="{json}">

    @Test("function_call с arguments как JSON-строкой парсится")
    func parsesFunctionCallTagWithJsonArguments() {
        let text = """
        <function_call name="write_file" arguments='{"file_path": "a.txt", "content": "hi"}'></function_call>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "write_file")
        #expect(args(calls[0], "file_path") == "a.txt")
        #expect(args(calls[0], "content") == "hi")
    }

    @Test("function_call с вложенными param-тегами парсится")
    func parsesFunctionCallTagWithParamChildren() {
        let text = """
        <function_call name="glob">
        <param name="pattern">**/*.swift</param>
        </function_call>
        """
        let calls = ExtraToolCallFormatParsers.parseAll(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "glob")
        #expect(args(calls[0], "pattern") == "**/*.swift")
    }

    // MARK: - JSON-аргументы строкой (Llama/OpenAI verbose) — центральный путь

    @Test("arguments как JSON-строка в ```tool блоке парсится")
    func parsesStringArgumentsInsideToolFence() {
        let text = """
        ```tool
        {"name": "grep", "arguments": "{\\"pattern\\": \\"needle\\", \\"path\\": \\"src\\"}"}
        ```
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "grep")
        #expect(args(calls[0], "pattern") == "needle")
        #expect(args(calls[0], "path") == "src")
    }

    @Test("tool_calls-контейнер с function/arguments-строкой парсится")
    func parsesToolCallsContainerWithStringArguments() {
        let text = """
        {"tool_calls": [{"type": "function", "function": {"name": "list_dir", "arguments": "{\\"path\\": \\".\\"}"}}]}
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "list_dir")
        #expect(args(calls[0], "path") == ".")
    }

    // MARK: - Чистота: не-DSML/не-инструментные теги не трогаем

    @Test("HTML-теги и проза не дают ложных вызовов")
    func ignoresForeignMarkup() {
        let text = """
        <div class="x">тело</div>
        <invoke>без атрибута name</invoke>
        <tool_use>без name</tool_use>
        <function_call>без name</function_call>
        """
        #expect(ExtraToolCallFormatParsers.parseAll(from: text).isEmpty)
    }
}
