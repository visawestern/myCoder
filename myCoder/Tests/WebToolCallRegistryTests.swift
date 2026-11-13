import Foundation
import Testing
@testable import myCoder

/// TDD for the tool-call registry (directive 2026-11-13, план п.8): every
/// vendor format must be recognized and stripped from visible prose; syntax
/// is validated deterministically against the concrete tool schema BEFORE
/// execution, and the internal model is consulted only for unknown/ambiguous
/// formats — to repair syntax, never to decide execution.
@MainActor
@Suite("Tool-call registry — ERNIE wrappers + deterministic schema validation + model repair")
struct WebToolCallRegistryTests {

    // MARK: - ERNIE wrapper (<ernie:tool_call>…<invoke name>…)

    @Test func ernieWrapperInnerInvokeParses() {
        let text = """
        <ernie:tool_call>
        <invoke name="list_dir"><parameter name="path">.</parameter></invoke>
        </ernie:tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: text)
        #expect(calls.count == 1)
        #expect(calls[0].name == "list_dir")
        #expect(calls[0].arguments["path"] == ".")
    }

    @Test func ernieWrapperIsStrippedFromVisibleText() {
        let text = """
        Проверю счётчики.
        <ernie:tool_call>
        <invoke name="list_dir"><parameter name="path">.</parameter></invoke>
        </ernie:tool_call>
        Готово.
        """
        let visible = ToolProtocolStripping.visibleText(from: text)
        #expect(!visible.contains("ernie"))
        #expect(!visible.contains("invoke"))
        #expect(visible.contains("Проверю счётчики."))
        #expect(visible.contains("Готово."))
    }

    @Test func unclosedErnieWrapperIsMalformed() {
        let text = """
        <ernie:tool_call>
        <invoke name="list_dir"><parameter name="path">.</parameter></invoke>
        """
        let malformed = WebToolProtocolEmulator.malformedToolCall(from: text)
        #expect(malformed != nil)
        #expect(malformed?.problem.lowercased().contains("ernie") ?? false)
    }

    // MARK: - Deterministic schema validation (stage 1 — no model involved)

    @Test func schemaRequiresWriteContentAndPath() {
        let missingContent = WebToolCall(name: "write_file", arguments: ["path": "a.txt"])
        #expect(WebToolProtocolEmulator.validate(missingContent, projectRoot: "/tmp") == .invalidArguments("missing required argument 'content' for write_file"))

        let missingPath = WebToolCall(name: "write_file", arguments: ["content": "x"])
        #expect(WebToolProtocolEmulator.validate(missingPath, projectRoot: "/tmp") == .invalidArguments("missing required argument 'path' for write_file"))

        let full = WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"])
        #expect(WebToolProtocolEmulator.validate(full, projectRoot: "/tmp") == nil)
    }

    @Test func schemaRequiresEditOldAndNew() {
        let call = WebToolCall(name: "edit_file", arguments: ["path": "a.swift", "old": "x"])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/tmp") == .invalidArguments("missing required argument 'new' for edit_file"))
    }

    @Test func schemaRequiresRunCommand() {
        let call = WebToolCall(name: "run_command", arguments: ["path": "x"])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/tmp") == .invalidArguments("missing required argument 'command' for run_command"))
    }

    @Test func schemaRequiresWebFetchUrl() {
        let call = WebToolCall(name: "web_fetch", arguments: ["limit": "100"])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/tmp") == .invalidArguments("missing required argument 'url' for web_fetch"))
    }

    @Test func lspOperationMustBeFromTheEnum() {
        let bad = WebToolCall(name: "lsp", arguments: ["operation": "dance", "path": "A.swift"])
        #expect(WebToolProtocolEmulator.validate(bad, projectRoot: "/tmp") == .invalidArguments("lsp operation 'dance' is not one of diagnostics|definition|references|hover|completion"))

        let good = WebToolCall(name: "lsp", arguments: ["operation": "diagnostics", "path": "A.swift"])
        #expect(WebToolProtocolEmulator.validate(good, projectRoot: "/tmp") == nil)
    }

    @Test func readSymbolRequiresIdOrPathPlusName() {
        let bare = WebToolCall(name: "read_symbol", arguments: ["path": "A.swift"])
        #expect(WebToolProtocolEmulator.validate(bare, projectRoot: "/tmp") == .invalidArguments("read_symbol needs either 'id' or both 'path' and 'name'"))

        let byID = WebToolCall(name: "read_symbol", arguments: ["id": "42"])
        #expect(WebToolProtocolEmulator.validate(byID, projectRoot: "/tmp") == nil)

        let byPair = WebToolCall(name: "read_symbol", arguments: ["path": "A.swift", "name": "foo"])
        #expect(WebToolProtocolEmulator.validate(byPair, projectRoot: "/tmp") == nil)
    }

    @Test func optionalArgToolsPassSchemaWithEmptyArguments() {
        for name in ["list_dir", "git_status", "git_diff", "git_log", "git_branch",
                     "git_push", "git_pull", "glob", "todo_read", "task_list", "skill"] {
            let call = WebToolCall(name: name, arguments: [:])
            #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/tmp") == nil, "\(name) must not demand arguments")
        }
    }

    @Test func schemaValidationCoversAliasesAfterCanonicalization() {
        // "Bash" is an alias; schema must still enforce `command`.
        let call = WebToolCall(name: "Bash", arguments: ["cmd": "pwd"])
        let error = WebToolProtocolEmulator.validate(call, projectRoot: "/tmp")
        #expect(error == .invalidArguments("missing required argument 'command' for run_command"))
    }

    @Test func invalidArgumentsExampleCarriesCorrectSyntax() {
        let message = WebToolProtocolEmulator.validationResultText(
            for: .invalidArguments("missing required argument 'content' for write_file"),
            callName: "write_file"
        )
        #expect(message.contains("validation error:"))
        #expect(message.contains("write_file"))
        #expect(message.contains("Correct call syntax:"))
    }

    // MARK: - Model repair (stage 2 — only for ambiguous/malformed blocks)

    @Test func repairRecoversAmbiguousBlockViaModel() async {
        // No deterministic parser understands this block: JSON with a non
        // canonical key shape. The repair path must produce a valid call.
        let bad = "```tool\n{\"input\":\"list_dir\",\"params\":{\"path\":\".\"}}\n```"
        let repaired = await WebToolCallRepairLogic.tryRepair(responseText: bad) { _ in
            """
            ```tool
            {"name": "list_dir", "args": {"path": "."}}
            ```
            """
        }
        let calls = try? #require(repaired)
        #expect(calls?.count == 1)
        #expect(calls?.first?.name == "list_dir")
        #expect(calls?.first?.arguments["path"] == ".")
    }

    @Test func repairSkipsWhenDeterministicParsingSucceeded() async {
        var modelCalled = false
        let good = "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \".\"}}\n```"
        let result = await WebToolCallRepairLogic.tryRepair(responseText: good) { _ in
            modelCalled = true
            return "{}"
        }
        #expect(result == nil)
        #expect(!modelCalled)
    }

    @Test func repairSkipsForPlainProse() async {
        var modelCalled = false
        let prose = "Я просто отвечаю на вопрос."
        let result = await WebToolCallRepairLogic.tryRepair(responseText: prose) { _ in
            modelCalled = true
            return "{}"
        }
        #expect(result == nil)
        #expect(!modelCalled)
    }

    @Test func repairReturnsNilWhenModelProducesNoValidCalls() async {
        let bad = "```tool\n{\"input\":\"list_dir\",\"params\":{\"path\":\".\"}}\n```"
        let result = await WebToolCallRepairLogic.tryRepair(responseText: bad) { _ in
            "Извините, я не нашёл вызовов."
        }
        #expect(result == nil)
    }
}
