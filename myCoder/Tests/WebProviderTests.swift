import Testing
import Foundation
@testable import myCoder

@Suite("Web provider config + vendors (plan Раздел 12 Блок 1)")
struct WebProviderConfigTests {

    @Test func vendorDefaultsPopulated() {
        #expect(WebChatVendor.kimi.defaultChatURL == "https://www.kimi.ai/")  // non-CN domain (2026-09-06)
        #expect(WebChatVendor.qwen.defaultChatURL == "https://chat.qwen.ai/")
        #expect(WebChatVendor.chatgpt.defaultChatURL == "https://chatgpt.com/")
        #expect(WebChatVendor.kimi.defaultModels.contains("k2-thinking"))
        // ChatGPT models list is empty by design (models change frequently)
        #expect(WebChatVendor.chatgpt.defaultModels.isEmpty)
    }

    @Test func configStartsWithoutGuessedWebModel() {
        let cfg = WebProviderConfig(vendor: .kimi)
        #expect(cfg.displayName == "Kimi")
        #expect(cfg.chatURL == "https://www.kimi.ai/")  // non-CN domain (2026-09-06)
        #expect(cfg.selectedModel.isEmpty)
        #expect(cfg.effort == .medium)
        #expect(cfg.toolCallDelayMs == 800)
        #expect(cfg.maxToolIterations == 25)
    }

    @Test func alwaysReady() {
        let cfg = WebProviderConfig(vendor: .qwen)
        #expect(cfg.isReady)               // always ready — ToS no longer blocks
    }

    @Test func configRoundTripsThroughCodable() throws {
        let cfg = WebProviderConfig(vendor: .chatgpt, effort: .high, toolCallDelayMs: 1200, acknowledgedToS: true)
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(WebProviderConfig.self, from: data)
        #expect(decoded == cfg)
        #expect(decoded.effort == .high)
        #expect(decoded.toolCallDelayMs == 1200)
    }

    @Test func russianEffortLabelsMapToDistinctLevels() {
        #expect(WebModelListParser.normalizeEffort("Быстрый", vendor: .kimi) == .low)
        #expect(WebModelListParser.normalizeEffort("Стандартный", vendor: .kimi) == .medium)
        #expect(WebModelListParser.normalizeEffort("Высокий", vendor: .kimi) == .high)
    }

    @Test func storePersistsAndUpserts() {
        let d = UserDefaults(suiteName: "web-providers-\(UUID().uuidString)")!
        let a = WebProviderConfig(vendor: .kimi, acknowledgedToS: true)
        WebProviderStore.save([a], defaults: d)
        #expect(WebProviderStore.load(defaults: d).count == 1)

        var updated = a
        updated.effort = .high
        let merged = WebProviderStore.upsert(updated, in: WebProviderStore.load(defaults: d))
        WebProviderStore.save(merged, defaults: d)
        let loaded = WebProviderStore.load(defaults: d)
        #expect(loaded.count == 1)
        #expect(loaded.first?.effort == .high)
    }
}

@Suite("Web tool-protocol emulator (plan Раздел 12 Блок 2)")
struct WebToolProtocolEmulatorTests {

    @Test func systemPreambleListsToolsAndFormat() {
        let preamble = WebToolProtocolEmulator.systemPreamble()
        #expect(preamble.contains("```tool"))
        #expect(preamble.contains("read_file"))
        #expect(preamble.contains("write_file"))
        #expect(preamble.contains("run_command"))
    }

    @Test func systemPreambleIncludesUserPrompt() {
        let preamble = WebToolProtocolEmulator.systemPreamble(userSystemPrompt: "Be terse.")
        #expect(preamble.hasPrefix("Be terse."))
    }

    @Test func parsesSingleToolCall() {
        let response = """
        Let me read that file.
        ```tool
        {"name": "read_file", "args": {"path": "src/main.swift"}}
        ```
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "src/main.swift")
    }

    @Test func parsesMultipleToolCalls() {
        let response = """
        ```tool
        {"name": "list_dir", "args": {"path": "."}}
        ```
        then
        ```tool
        {"name": "read_file", "args": {"path": "README.md"}}
        ```
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 2)
        #expect(calls[0].name == "list_dir")
        #expect(calls[1].name == "read_file")
    }

    @Test func parsesInformalBracketToolCall() {
        // Round 12: a real web model answered "[tool call: LS with path "."]"
        // instead of a strict ```tool block, so the analysis stalled at step 1.
        let response = """
        Я проанализирую проект. Начну с изучения структуры.
        [tool call: LS with path "."]
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_dir")
        #expect(calls.first?.arguments["path"] == ".")
    }

    @Test func parsesInformalToolCallWithEqualsArgs() {
        let response = "[tool call: read_file with path=\"README.md\"]"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "README.md")
    }

    @Test func parsesTaggedToolCallXML() {
        // The exact format big-pickle / MiMo-style models emit (observed in a
        // real session): <tool_call>NAME<arg_key>k</arg_key><arg_value>v</arg_value></tool_call>.
        let response = """
        ## ТЕСТ 1: pwd
        **Цель:** проверить окружение<tool_call>execute_command<arg_key>command</arg_key><arg_value>pwd</arg_value></tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "run_command")
        #expect(calls.first?.arguments["command"] == "pwd")
    }

    @Test func parsesTaggedToolCallMultipleArgs() {
        let response = "<tool_call>read_file<arg_key>path</arg_key><arg_value>src/main.swift</arg_value></tool_call>"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "src/main.swift")
    }

    @Test func parsesTaggedToolCallAfterFenceWithAmpersandCommand() {
        // Real observed output: prose + a fenced bash block, then a <tool_call>
        // whose command argValue contains `&&`, spaces and quotes. The XML
        // parser must still pick it up and canonicalize execute_command.
        let response = """
        ### 🔹 Тест 1: Проверка текущей директории
        ```bash
        pwd
        ```
        *(Безопасно — просто показывает путь)*<tool_call>execute_command<arg_key>command</arg_key><arg_value>pwd && echo "---" && whoami && echo "---" && uname -a</arg_value></tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "run_command")
        #expect(calls.first?.arguments["command"] == #"pwd && echo "---" && whoami && echo "---" && uname -a"#)
        #expect(!WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func taggedToolCallIsNotFinalResponse() {
        // A <tool_call> block must not be treated as a plain-text final answer,
        // otherwise the agentic loop stops and never executes the tool.
        let response = "Работаю<tool_call>run_command<arg_key>command</arg_key><arg_value>ls -la</arg_value></tool_call>"
        #expect(!WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func parsesMultilineTaggedToolCalls() {
        // Live MiMo-style models pretty-print the XML across lines (observed in
        // a real session). The parser must not silently drop these, otherwise
        // the agentic loop stalls showing raw unexecuted tool calls.
        let response = """
        Начинаю! Сначала найдём файл технического задания в текущей папке проекта.
        <tool_call>list_dir<arg_key>path</arg_key>
        <arg_value>.</arg_value>
        </tool_call>
        <tool_call>glob
        <arg_key>pattern</arg_key>
        <arg_value>**/*.{txt,md}</arg_value>
        </tool_call>
        """
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 2)
        #expect(calls[0].name == "list_dir")
        #expect(calls[0].arguments["path"] == ".")
        #expect(calls[1].name == "glob")
        #expect(calls[1].arguments["pattern"] == "**/*.{txt,md}")
        #expect(!WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func parsesFencedToolCallWithoutTrailingNewline() {
        let response = "Смотрю файл.\n```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"README.md\"}}```"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "README.md")
    }

    @Test func parsesShortTaggedToolCall() {
        // Audit 2026-09-11 (Kimi live): the model emits exactly the short XML
        // form taught by the preamble — `<list_dir>path=.</list_dir>` — and
        // the turn died with raw tool text as the "answer" because no parser
        // handled it.
        let response = "Смотрю папку.\n<list_dir>path=.</list_dir>"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_dir")
        #expect(calls.first?.arguments["path"] == ".")
        #expect(!WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func parsesShortTaggedToolCallQuotedArgs() {
        let response = #"<read_file>path="my dir/file.md" limit=5</read_file>"#
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "my dir/file.md")
        #expect(calls.first?.arguments["limit"] == "5")
    }

    @Test func shortTaggedUnknownTagsIgnored() {
        // Arbitrary HTML must not become tool calls.
        let response = "Текст <div>path=.</div> и <b>важно</b>"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.isEmpty)
        #expect(WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func fencedJSONNumericAndBoolArgsInterpolate() {
        // Live 2026-09-12: the model emitted "limit": 115, "offset": 115 and
        // both arrived as the literal text "\(v)" — offset was silently
        // ignored 3× in a row. Non-string JSON args must stringify.
        let response = "Читаю.\n```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"TZ-Bezdna-v3.md\", \"limit\": 115, \"offset\": 20}}\n```"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["limit"] == "115")
        #expect(calls.first?.arguments["offset"] == "20")
        #expect(calls.first?.arguments["path"] == "TZ-Bezdna-v3.md")
        let diff = "Дифф.\n```tool\n{\"name\": \"git_diff\", \"args\": {\"path\": \".\", \"staged\": true}}\n```"
        let diffCalls = WebToolProtocolEmulator.parseToolCalls(from: diff)
        #expect(diffCalls.first?.arguments["staged"] == "true")
        // JSON false canonicalizes too (not "0").
        let unstaged = "Дифф.\n```tool\n{\"name\": \"git_diff\", \"args\": {\"path\": \".\", \"staged\": false}}\n```"
        #expect(WebToolProtocolEmulator.parseToolCalls(from: unstaged).first?.arguments["staged"] == "false")
    }

    @Test func fencedJSONWithNBSPParses() {
        // parseSingleCall must normalize a REAL NBSP inside fenced JSON
        // (the old code normalized the literal 8-char text instead — dead
        // code — so NBSP-bearing calls silently dropped).
        let nbsp = String(decoding: [0xC2, 0xA0] as [UInt8], as: UTF8.self)
        let response = "Смотрю.\n```tool\n{\"name\": \"list_dir\", \"args\": {\"path\":" + nbsp + "\".\"}}\n```"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["path"] == ".")
    }

    @Test func truthyFlagAcceptsAllSpellings() {
        #expect(WebToolProtocolEmulator.isTruthyFlag("true"))
        #expect(WebToolProtocolEmulator.isTruthyFlag("TRUE"))
        #expect(WebToolProtocolEmulator.isTruthyFlag("1"))
        #expect(WebToolProtocolEmulator.isTruthyFlag("yes"))
        #expect(!WebToolProtocolEmulator.isTruthyFlag("false"))
        #expect(!WebToolProtocolEmulator.isTruthyFlag("0"))
        #expect(!WebToolProtocolEmulator.isTruthyFlag(nil))
        #expect(!WebToolProtocolEmulator.isTruthyFlag(""))
    }

    @Test func shortTaggedReadWindowArgs() {
        // Full Claude Code Read form in short XML: path + limit + offset.
        let response = "<read_file>path=TZ-Bezdna-v3.md limit=115 offset=20</read_file>"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["limit"] == "115")
        #expect(calls.first?.arguments["offset"] == "20")
    }

    @Test func informalKeyValueArgs() {
        // [tool call: read with path=X limit=10 offset='5'] — bare and
        // single-quoted k=v pairs in the informal syntax.
        let response = "[tool call: read with path=TZ-Bezdna-v3.md limit=10 offset='5']"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        #expect(calls.first?.arguments["path"] == "TZ-Bezdna-v3.md")
        #expect(calls.first?.arguments["limit"] == "10")
        #expect(calls.first?.arguments["offset"] == "5")
    }

    @Test func toolRefusalRUDetected() {
        #expect(WebRefusalLogic.isToolRefusal("Я не могу выполнить эти вызовы из текущего чата: инструменты недоступны в этом окружении."))
        #expect(WebRefusalLogic.isToolRefusal("У меня нет доступа к вашему компьютеру, пришлите файлы."))
        #expect(WebRefusalLogic.isToolRefusal("С прошлого раза у меня нет контекста задачи."))
    }

    @Test func toolRefusalENDetected() {
        #expect(WebRefusalLogic.isToolRefusal("I don't have access to your computer, so I can't list files."))
        #expect(WebRefusalLogic.isToolRefusal("Tools are not available in this environment."))
        #expect(WebRefusalLogic.isToolRefusal("I am a sandboxed model without filesystem access."))
    }

    @Test func toolRefusalKimiIdentityDetected() {
        // Live 2026-09-12 (verbatim excerpts): Kimi asserts its own
        // sandbox/ipython identity instead of emitting blocks. The old
        // markers missed this class entirely and the turn died.
        #expect(WebRefusalLogic.isToolRefusal("я не Claude Code и не могу «испускать блоки» в формате его тулов"))
        #expect(WebRefusalLogic.isToolRefusal("у меня другой набор инструментов, и они выполняются в моей среде (песочнице с /mnt/agents)"))
        #expect(WebRefusalLogic.isToolRefusal("мои тулзы не имеют доступа к вашей файловой системе"))
        #expect(WebRefusalLogic.isToolRefusal("I am not Claude Code, I have a different set of tools and my tools run in a sandbox"))
    }

    @Test func genuineAnswersAreNotRefusals() {
        #expect(!WebRefusalLogic.isToolRefusal("В папке 4 элемента: .DS_Store, .git, .mycoder, TZ-Bezdna-v3.md."))
        #expect(!WebRefusalLogic.isToolRefusal("Готово: тесты прошли, 12 passed."))
        #expect(!WebRefusalLogic.isToolRefusal("Уточните, пожалуйста, путь к файлу, который нужно прочитать."))
        #expect(!WebRefusalLogic.isToolRefusal(""))
        #expect(!WebRefusalLogic.isToolRefusal("ok"))
        // Decoys: sandbox mentions that are NOT refusals.
        #expect(!WebRefusalLogic.isToolRefusal("Прогони тесты в песочнице и покажи результат."))
        #expect(!WebRefusalLogic.isToolRefusal("Не могу найти файл — уточните путь."))
        #expect(!WebRefusalLogic.isToolRefusal("У меня другой вопрос по коду выше."))
    }

    @Test func systemPreambleTeachesBothFormatsAndTools() {
        let preamble = WebToolProtocolEmulator.systemPreamble(projectRoot: "/proj", isGitRepo: true)
        #expect(preamble.contains("```tool"))
        #expect(preamble.contains("<tool_name>"))
        // Compact form (audit 2026-09-08): cwd/git/date on one line so the
        // preamble stays under the ~4000-byte vendor paste limit.
        #expect(preamble.contains("cwd: /proj"))
        #expect(preamble.contains("git: yes"))
        #expect(preamble.contains("read_file"))
        #expect(preamble.contains("run_command"))
        // read_file teaches paging (live 2026-09-12: offset was ignored).
        #expect(preamble.contains("limit"))
        #expect(preamble.contains("offset"))
        // The whole preamble must fit ONE vendor paste (Kimi converts larger
        // pastes into .txt attachments, which the model then can not follow).
        #expect((preamble.data(using: .utf8)?.count ?? 0) < 3900)
    }

    @Test func toolNameAliasesAreCaseInsensitive() {
        #expect(WebToolProtocolEmulator.canonicalToolName("LS") == "list_dir")
        #expect(WebToolProtocolEmulator.canonicalToolName("ls") == "list_dir")
        #expect(WebToolProtocolEmulator.canonicalToolName("Read") == "read_file")
        #expect(WebToolProtocolEmulator.canonicalToolName("run_command") == "run_command")
        #expect(WebToolProtocolEmulator.canonicalToolName("Grep") == "grep")
        #expect(WebToolProtocolEmulator.canonicalToolName("Write") == "write_file")
    }

    @Test func informalToolCallIsNotFinalResponse() {
        // An unrecognized-syntax call must NOT be treated as a final answer,
        // otherwise the agentic loop stops and the analysis stalls.
        let response = "[tool call: LS with path \".\"]"
        #expect(!WebToolProtocolEmulator.isFinalResponse(response))
    }

    @Test func finalResponseHasNoToolCall() {
        #expect(WebToolProtocolEmulator.isFinalResponse("All done! The bug is fixed."))
        #expect(!WebToolProtocolEmulator.isFinalResponse("```tool\n{\"name\":\"grep\",\"args\":{}}\n```"))
    }

    @Test func formatToolResultProducesParseableBlock() {
        let block = WebToolProtocolEmulator.formatToolResult(name: "read_file", result: "line1\nline2")
        #expect(block.contains("```tool_result"))
        #expect(block.contains("read_file"))
        // The result must be JSON-escaped (newline → \n)
        #expect(block.contains("line1"))
    }

    @Test func stopLoopOnFinalOrLimit() {
        #expect(WebToolProtocolEmulator.shouldStopLoop(iteration: 3, maxIterations: 25, lastResponse: "done"))
        #expect(WebToolProtocolEmulator.shouldStopLoop(iteration: 25, maxIterations: 25, lastResponse: "```tool\n{}\n```"))
        #expect(!WebToolProtocolEmulator.shouldStopLoop(iteration: 2, maxIterations: 25, lastResponse: "```tool\n{\"name\":\"grep\"}\n```"))
    }

    @Test func validateRejectsPathEscape() {
        let call = WebToolCall(name: "read_file", arguments: ["path": "../../etc/passwd"])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/home/user/proj") == .pathEscapesProject("../../etc/passwd"))
    }

    @Test func validateAcceptsInsidePath() {
        let call = WebToolCall(name: "read_file", arguments: ["path": "src/main.swift"])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/home/user/proj") == nil)
    }

    @Test func validateRejectsUnknownTool() {
        let call = WebToolCall(name: "delete_everything", arguments: [:])
        #expect(WebToolProtocolEmulator.validate(call, projectRoot: "/home/user/proj") == .unknownTool("delete_everything"))
    }

    @Test func destructiveToolsRequireApproval() {
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "write_file", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "edit_file", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "todo_write", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "git_push", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "task", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "run_command", arguments: [:])))
        #expect(!WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "read_file", arguments: [:])))
    }

    @Test func pathInsideRootHandlesAbsoluteAndRelative() {
        #expect(WebToolProtocolEmulator.isPathInsideRoot("src/a.swift", root: "/proj"))
        #expect(WebToolProtocolEmulator.isPathInsideRoot("/proj/src/a.swift", root: "/proj"))
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("/etc/passwd", root: "/proj"))
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("../x", root: "/proj"))
    }

    // MARK: - Audit ARCH-06: symlink traversal must not escape the project root

    private func makeTempSymlinkProject() throws -> (root: String, cleanup: () -> Void) {
        let fm = FileManager.default
        let base = NSTemporaryDirectory() + "/mycoder-symlink-\(UUID().uuidString)"
        let root = base + "/root"
        let outside = base + "/outside"
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/src", withIntermediateDirectories: true)
        // A symlink INSIDE the project root pointing OUTSIDE of it.
        try fm.createSymbolicLink(atPath: root + "/escape", withDestinationPath: outside)
        let cleanup: () -> Void = { try? fm.removeItem(atPath: base) }
        return (root, cleanup)
    }

    @Test func symlinkInsideRootPointingOutsideIsRejected() throws {
        let (root, cleanup) = try makeTempSymlinkProject()
        defer { cleanup() }
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("escape/secret.txt", root: root),
                "A symlink inside the root must not smuggle an out-of-root target past the check")
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("escape", root: root))
    }

    @Test func symlinkedRootItselfStillResolves() throws {
        let (root, cleanup) = try makeTempSymlinkProject()
        defer { cleanup() }
        let fm = FileManager.default
        // A symlink TO the project root (e.g. /tmp -> /private/tmp) must keep
        // legitimate in-root paths working.
        let link = NSTemporaryDirectory() + "/mycoder-rootlink-\(UUID().uuidString)"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: root)
        defer { try? fm.removeItem(atPath: link) }
        #expect(WebToolProtocolEmulator.isPathInsideRoot("src/a.swift", root: link))
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("../x", root: link))
    }

    @Test func missingWriteTargetInsideRootStillPasses() throws {
        let (root, cleanup) = try makeTempSymlinkProject()
        defer { cleanup() }
        // write_file targets do not exist yet; resolution must not break them.
        #expect(WebToolProtocolEmulator.isPathInsideRoot("src/new-file.swift", root: root))
    }

    // MARK: - Audit regression: lexical `..` resolution must terminate and
    // be correct (URL.deletingLastPathComponent is a no-op on trailing "..",
    // which spun the first ARCH-06 fix in an infinite loop).

    @Test func dotDotPathsRejectOrAcceptLexically() {
        // `..` escaping a non-existent root must be rejected, not accepted.
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("../x", root: "/proj"))
        #expect(!WebToolProtocolEmulator.isPathInsideRoot("a/../../x", root: "/proj"))
        // `..` that stays inside after lexical resolution is still inside.
        #expect(WebToolProtocolEmulator.isPathInsideRoot("a/../b.swift", root: "/proj"))
    }
}

@Suite("Web session + anti-ban logic (plan Раздел 12 Блок 3)")
struct WebSessionLogicTests {

    @Test func detectsCaptchaMarkers() {
        #expect(WebSessionLogic.detectCaptcha(pageText: "Please complete the reCAPTCHA", url: ""))
        #expect(WebSessionLogic.detectCaptcha(pageText: "", url: "https://challenges.cloudflare.com/x"))
        #expect(WebSessionLogic.detectCaptcha(pageText: "Verify you are human", url: ""))
        #expect(!WebSessionLogic.detectCaptcha(pageText: "Hello, how can I help?", url: "https://kimi.com/chat"))
    }

    @Test func inferStateCaptchaWins() {
        let s = WebSessionLogic.inferState(currentURL: "https://kimi.com", hasChatInput: true,
                                           pageText: "verify you are human")
        #expect(s == .captchaRequired)
    }

    @Test func inferStateLoggedOutOnLoginURL() {
        let s = WebSessionLogic.inferState(currentURL: "https://chatgpt.com/auth/login",
                                           hasChatInput: false, pageText: "Sign in")
        #expect(s == .loggedOut)
    }

    @Test func inferStateConnectedWhenChatPresent() {
        let s = WebSessionLogic.inferState(currentURL: "https://chat.qwen.ai/c/123",
                                           hasChatInput: true, pageText: "chat")
        #expect(s == .connected)
    }

    @Test func inferStateLimitReachedOnPricingRedirect() {
        // Audit 2026-09-09 (Kimi live): submitting on /agent with exhausted
        // quota redirects to /membership/pricing?from=okc_limit_notification.
        // A pricing page has no chat input — it must read as limitReached,
        // never as loggedOut (which would tell the user to log in).
        let s = WebSessionLogic.inferState(
            currentURL: "https://www.kimi.ai/membership/pricing?from=okc_limit_notification",
            hasChatInput: false, pageText: "Kimi Membership")
        #expect(s == .limitReached)
    }

    @Test func inferStateLimitReachedOnQueueBanner() {
        let s = WebSessionLogic.inferState(
            currentURL: "https://www.kimi.ai/agent",
            hasChatInput: true,
            pageText: "Слишком много людей сейчас общаются с Kimi. Подпишитесь!")
        #expect(s == .limitReached)
    }

    @Test func inferStateLimitBeatsCaptchaFreePricingText() {
        #expect(WebSessionLogic.detectLimitReached(
            pageText: "", url: "https://www.kimi.ai/membership/pricing"))
        #expect(!WebSessionLogic.detectLimitReached(
            pageText: "Hello, how can I help?", url: "https://www.kimi.ai/chat/1"))
    }

    @Test func sessionExpiredWhenAllCookiesPast() {
        #expect(WebSessionLogic.isSessionExpired(cookieExpiryEpochs: [100, 200], now: 300))
        #expect(!WebSessionLogic.isSessionExpired(cookieExpiryEpochs: [100, 5000], now: 300))
        #expect(WebSessionLogic.isSessionExpired(cookieExpiryEpochs: [], now: 300))
    }

    @Test func keepAliveDueAfterInterval() {
        #expect(WebSessionLogic.keepAliveDue(lastPing: 0, now: 130, intervalSec: 120))
        #expect(!WebSessionLogic.keepAliveDue(lastPing: 0, now: 60, intervalSec: 120))
    }

    @Test func antiBanDelayAppliesJitterWithinBounds() {
        // randomUnit 0.5 → offset 0 → exactly base
        #expect(WebAntiBanTiming.delayMs(base: 800, jitterPercent: 20, randomUnit: 0.5) == 800)
        // randomUnit 0 → -span → base - 160 = 640
        #expect(WebAntiBanTiming.delayMs(base: 800, jitterPercent: 20, randomUnit: 0) == 640)
        // randomUnit ~1 → +span → ~ base + 160
        let high = WebAntiBanTiming.delayMs(base: 800, jitterPercent: 20, randomUnit: 0.999)
        #expect(high >= 955 && high <= 960)
    }

    @Test func antiBanDelayZeroBaseIsZero() {
        #expect(WebAntiBanTiming.delayMs(base: 0, randomUnit: 0.5) == 0)
    }

    @Test func readOnlyCommandRunsAtAnyAccessLevel() {
        // The exact command from the real session must run even though the
        // user's access level is below fullAccess.
        let call = WebToolCall(name: "run_command",
                               arguments: ["command": #"pwd && echo "---" && whoami && uname -a"#])
        #expect(WebToolAccessGate.permission(for: call, accessLevel: .askBeforeChanges) == .allow)
        #expect(WebToolAccessGate.permission(for: call, accessLevel: .editAutomatically) == .allow)
        #expect(WebToolAccessGate.permission(for: call, accessLevel: .fullAccess) == .allow)
    }

    @Test func mutatingCommandStillRequiresApprovalBelowFull() {
        let rm = WebToolCall(name: "run_command", arguments: ["command": "rm -rf build"])
        #expect(WebToolAccessGate.permission(for: rm, accessLevel: .askBeforeChanges) == .requireApproval)
        #expect(WebToolAccessGate.permission(for: rm, accessLevel: .editAutomatically) == .requireApproval)
        #expect(WebToolAccessGate.permission(for: rm, accessLevel: .fullAccess) == .allow)
    }

    @Test func readOnlyGitSubcommandsAllowedMutatingGitGated() {
        let log = WebToolCall(name: "run_command", arguments: ["command": "git log --oneline -5"])
        #expect(WebToolAccessGate.permission(for: log, accessLevel: .askBeforeChanges) == .allow)
        let checkout = WebToolCall(name: "run_command", arguments: ["command": "git checkout main"])
        #expect(WebToolAccessGate.permission(for: checkout, accessLevel: .editAutomatically) == .requireApproval)
        #expect(WebToolAccessGate.permission(for: checkout, accessLevel: .fullAccess) == .allow)
    }
}

@Suite("Truncated tool-call stub recovery (audit 2026-09-08)")
struct TruncatedToolCallStubTests {
    @Test func streamCutCallIsRecoveredNotFinal() {
        // Live Qwen: the stream cut the answer mid-JSON. It is a tool call,
        // never a final answer, and the loop must ask the model to re-emit.
        let truncated = "call {\"name\": \"list_dir\", \"arguments"
        #expect(!WebToolProtocolEmulator.isFinalResponse(truncated))
        let calls = WebToolProtocolEmulator.parseToolCalls(from: truncated)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_dir")
        #expect(calls.first?.arguments["__mycoder_truncated"] == "1")
    }

    @Test func completeFencedCallStillParsesNormally() {
        let complete = "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \".\"}}\n```"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: complete)
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["__mycoder_truncated"] == nil)
        #expect(calls.first?.arguments["path"] == ".")
    }

    @Test func plainTextWithoutCallIsFinal() {
        #expect(WebToolProtocolEmulator.isFinalResponse("Here is the listing: a, b, c"))
    }

    @Test func unknownToolNameStaysFinal() {
        // A truncated JSON naming an unknown tool is honest garbage — do not
        // invent a tool call from it.
        let garbage = "call {\"name\": \"not_a_tool\", \"arguments"
        #expect(WebToolProtocolEmulator.isFinalResponse(garbage))
    }
}


@Suite("Qwen truncated XML tool-call recovery")
struct QwenTruncatedXMLTests {
    @Test func qwenLiveTruncatedResponseIsToolCall() {
        // Verbatim live response (2026-09-08): the stream cut mid-tag; this
        // is neither a final answer nor an executable call — it must parse as
        // a truncated list_dir stub so the driver asks the model to re-emit.
        let live = "<tool_name>list_dir</tool_name> \u{27E8}path\u{27E9} \u{27E8}arg_value\u{27E9} . \u{27E8}/arg_value\u{27E9}"
        #expect(!WebToolProtocolEmulator.isFinalResponse(live))
        let calls = WebToolProtocolEmulator.parseToolCalls(from: live)
        #expect(calls.contains { $0.name == "list_dir" })
    }
}

@Suite("Unfenced NBSP JSON tool-call recovery (Qwen live)")
struct UnfencedNBSPToolCallTests {
    @Test func qwenBrokenFenceWithNBSPStillParses() {
        // Verbatim live shape (2026-09-08): no backticks, NBSP inside JSON,
        // a stray counter line before the object.
        let live = "tool\n\n\n1\n{\"name\":\u{00A0}\"list_dir\",\u{00A0}\"args\":\u{00A0}{\"path\":\u{00A0}\".\"}}"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: live)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_dir")
        #expect(calls.first?.arguments["path"] == ".")
    }

    @Test func plainUnfencedJSONParses() {
        let plain = "Here you go: {\"name\": \"read_file\", \"args\": {\"path\": \"README.md\"}}"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: plain)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
    }

    @Test func truncatedJSONStillFallsBackToStub() {
        let truncated = "call {\"name\": \"list_dir\", \"arguments"
        // No balanced object → the stub detector path stays authoritative.
        let calls = WebToolProtocolEmulator.parseToolCalls(from: truncated)
        #expect(calls.count == 1)
        #expect(calls.first?.arguments["__mycoder_truncated"] == "1")
    }
}

@Suite("Truncated tool_name prefix recovery (Qwen live)")
struct TruncatedToolNamePrefixTests {
    @Test func cutInsideToolNameIsRecovered() {
        // Live (2026-09-08): the stream died inside the name — "<tool_name>list".
        let live = "<tool_name>list"
        #expect(!WebToolProtocolEmulator.isFinalResponse(live))
        let calls = WebToolProtocolEmulator.parseToolCalls(from: live)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_dir")
        #expect(calls.first?.arguments["__mycoder_truncated"] == "1")
    }

    @Test func completeToolNamePrefixIsNotMistakenForCut() {
        // "<tool_name>list_dir</tool_name>..." — the full name path above
        // handles it; the prefix detector must not fire.
        let complete = "<tool_name>grep</tool_name>⟨pattern⟩x⟨/pattern⟩⟨/tool_name⟩"
        let calls = WebToolProtocolEmulator.parseToolCalls(from: complete)
        #expect(calls.allSatisfy { $0.arguments["__mycoder_truncated"] == nil })
    }
}
