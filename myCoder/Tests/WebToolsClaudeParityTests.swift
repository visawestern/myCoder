import Testing
import Foundation
@testable import myCoder

/// Claude Code parity for the emulated tool protocol.
/// Reference: https://code.claude.com/docs/en/tools-reference.md
/// Honest scope note: Claude Code lists ~45 built-ins and reaches "75+"
/// only with MCP servers + skills. We add what maps to REAL executors:
/// web_fetch (HTTP GET), skill (installed SKILL.md), task_create/list/update
/// (backed by the todo store). Deliberately NOT added: web_search (no search
/// backend — would be a stub), LSP (no language server), Notebook* (no
/// notebook runtime), plan-mode toggles (UI modes, not tools).
@Suite("Web tools — Claude Code parity (aliases, args, new tools)")
struct WebToolsClaudeParityTests {

    // MARK: - New tools exist with schemas and docs

    @Test func newToolsHaveSchemasAndDescriptions() {
        for tool in [WebEmulatedTool.webFetch, WebEmulatedTool.skill,
                     WebEmulatedTool.taskCreate, WebEmulatedTool.taskList,
                     WebEmulatedTool.taskUpdate] as [WebEmulatedTool] {
            #expect(!tool.argumentSchema.isEmpty, "\(tool.rawValue) needs a schema")
            #expect(!tool.description.isEmpty, "\(tool.rawValue) needs a description")
            #expect(!tool.isCore, "\(tool.rawValue) must stay out of the minimal core profile")
        }
        #expect(WebEmulatedTool.webFetch.rawValue == "web_fetch")
        #expect(WebEmulatedTool.skill.rawValue == "skill")
        #expect(WebEmulatedTool.taskCreate.rawValue == "task_create")
        #expect(WebEmulatedTool.taskList.rawValue == "task_list")
        #expect(WebEmulatedTool.taskUpdate.rawValue == "task_update")
    }

    // MARK: - Aliases: every model spelling resolves to the right tool

    @Test func anthropicPascalCaseAliases() {
        let cases: [(String, String)] = [
            ("Read", "read_file"), ("Edit", "edit_file"),
            ("Write", "write_file"), ("Bash", "run_command"),
            ("Glob", "glob"), ("Grep", "grep"),
            ("Task", "task"), ("TodoWrite", "todo_write"),
            ("TodoRead", "todo_read"), ("WebFetch", "web_fetch"),
            ("Skill", "skill"), ("TaskCreate", "task_create"),
            ("TaskList", "task_list"), ("TaskUpdate", "task_update"),
        ]
        for (alias, canonical) in cases {
            #expect(WebToolProtocolEmulator.canonicalToolName(alias) == canonical,
                    "\(alias) should resolve to \(canonical)")
        }
    }

    @Test func commonVariantAliases() {
        let cases: [(String, String)] = [
            ("cat", "read_file"), ("ls_dir", "list_dir"),
            ("apply_patch", "edit_file"), ("str_replace", "edit_file"),
            ("create_file", "write_file"), ("rg", "grep"), ("ripgrep", "grep"),
            ("execute", "run_command"), ("sh", "run_command"), ("bash", "run_command"),
            ("cmd", "run_command"), ("find_files", "glob"),
            ("git-commit", "git_commit"), ("read-file", "read_file"),
            ("todo-write", "todo_write"), ("webfetch", "web_fetch"),
            ("fetch", "web_fetch"), ("web_fetch_url", "web_fetch"),
            ("use_skill", "skill"), ("load_skill", "skill"),
            ("subagent", "task"), ("spawn", "task"),
            ("todos", "todo_read"),
        ]
        for (alias, canonical) in cases {
            #expect(WebToolProtocolEmulator.canonicalToolName(alias) == canonical,
                    "\(alias) should resolve to \(canonical)")
        }
    }

    // MARK: - Argument-name normalization across model families

    @Test func pathArgumentVariants() {
        for key in ["path", "file_path", "filepath", "file", "filename", "target_file"] {
            let args = WebToolProtocolEmulator.normalizedArguments(
                for: .readFile, from: [key: "src/a.swift"])
            #expect(args["path"] == "src/a.swift", "key \(key) must normalize to path")
        }
    }

    @Test func editArgumentVariants() {
        let args = WebToolProtocolEmulator.normalizedArguments(
            for: .editFile,
            from: ["file_path": "a.txt", "old_string": "x", "new_string": "y"])
        #expect(args["path"] == "a.txt")
        #expect(args["old"] == "x")
        #expect(args["new"] == "y")
    }

    @Test func commandArgumentVariants() {
        for key in ["command", "cmd", "cmdline", "bash_command", "shell_command"] {
            let args = WebToolProtocolEmulator.normalizedArguments(
                for: .runCommand, from: [key: "ls"])
            #expect(args["command"] == "ls", "key \(key) must normalize to command")
        }
    }

    @Test func grepArgumentVariants() {
        let args = WebToolProtocolEmulator.normalizedArguments(
            for: .grep, from: ["regex": "foo.*", "directory": "src"])
        #expect(args["pattern"] == "foo.*")
        #expect(args["path"] == "src")
    }

    @Test func canonicalArgsPassThroughUntouched() {
        let args = WebToolProtocolEmulator.normalizedArguments(
            for: .readFile, from: ["path": "a.txt", "limit": "10"])
        #expect(args == ["path": "a.txt", "limit": "10"])
    }

    // MARK: - Preamble budget with the bigger catalog

    @Test func fullPreambleStillFitsVendorPasteLimit() {
        let preamble = WebToolProtocolEmulator.systemPreamble(projectRoot: "/proj", isGitRepo: true)
        #expect(preamble.contains("web_fetch"))
        #expect(preamble.contains("skill"))
        #expect(preamble.contains("task_create"))
        #expect((preamble.data(using: .utf8)?.count ?? 0) < 3900)
    }

    // MARK: - Gate classification for new tools

    @Test func readOnlyNewToolsNeedNoApproval() {
        #expect(!WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "web_fetch", arguments: [:])))
        #expect(!WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "skill", arguments: [:])))
        #expect(!WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "task_list", arguments: [:])))
    }

    @Test func mutatingTaskToolsRequireApproval() {
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "task_create", arguments: [:])))
        #expect(WebToolProtocolEmulator.requiresApproval(WebToolCall(name: "task_update", arguments: [:])))
    }

    // MARK: - Executor: aliases + normalized args execute identically

    private func makeTempRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aliasCallExecutesLikeCanonical() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        // Anthropic PascalCase + foreign arg spelling must read the file.
        let viaAlias = await exec.execute(WebToolCall(name: "Read", arguments: ["file_path": "a.txt"]))
        let viaCanonical = await exec.execute(WebToolCall(name: "read_file", arguments: ["path": "a.txt"]))
        #expect(viaAlias == viaCanonical)
        #expect(viaAlias.contains("hello"))
    }

    @Test func hyphenatedCallExecutes() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "read-file", arguments: ["path": "a.txt"]))
        #expect(result.contains("hello"))
    }

    @Test func aliasOfGatedToolStillRequiresApproval() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        // "Bash" must face the run_command gate, not slip through as unknown.
        // Use a mutating command: read-only ones (echo/ls/cat) are allowed.
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .askBeforeChanges)
        let result = await exec.execute(WebToolCall(name: "Bash", arguments: ["cmd": "touch probe.txt"]))
        #expect(result.contains("approval") || result.contains("Approval"))
        #expect(!((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).contains("probe.txt"))
    }

    // MARK: - skill tool

    @Test func skillListsInstalledSkills() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let home = try makeTempRoot(prefix: "mimo-home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".mycoder/skills/demo", isDirectory: true),
            withIntermediateDirectories: true)
        try "# Demo skill".write(
            to: home.appendingPathComponent(".mycoder/skills/demo/SKILL.md"),
            atomically: true, encoding: .utf8)
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess,
                                          homeDirectory: home)
        let listed = await exec.execute(WebToolCall(name: "skill", arguments: [:]))
        #expect(listed.contains("demo"), "list must name the installed skill, got: \(listed)")
        let read = await exec.execute(WebToolCall(name: "skill", arguments: ["name": "demo"]))
        #expect(read.contains("# Demo skill"))
        let missing = await exec.execute(WebToolCall(name: "skill", arguments: ["name": "nope"]))
        #expect(missing.contains("error"))
        #expect(missing.contains("demo"), "unknown skill must suggest installed ones")
    }

    @Test func skillWithNoSkillsInstalledIsHonest() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let home = try makeTempRoot(prefix: "mimo-home-empty")
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess,
                                          homeDirectory: home)
        let listed = await exec.execute(WebToolCall(name: "skill", arguments: [:]))
        #expect(listed.contains("no installed skills"))
    }

    // MARK: - task_create / task_list / task_update

    @Test func taskCreateListUpdateRoundTrip() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let created = await exec.execute(
            WebToolCall(name: "task_create", arguments: ["content": "Write tests"]))
        #expect(created.hasPrefix("ok"), "create must succeed, got: \(created)")
        let listed = await exec.execute(WebToolCall(name: "task_list", arguments: [:]))
        #expect(listed.contains("Write tests"))
        #expect(listed.contains("pending"))
        // Extract the generated id from the list line "[pending] <id>: ..."
        let id = listed.split(separator: "\n").first
            .flatMap { line -> String? in
                let parts = line.split(separator: ":")
                guard parts.count >= 2 else { return nil }
                return String(parts[0]).replacingOccurrences(of: "[pending] ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } ?? ""
        #expect(!id.isEmpty)
        let updated = await exec.execute(
            WebToolCall(name: "TaskUpdate", arguments: ["task_id": id, "status": "done"]))
        #expect(updated.contains("completed"), "done must normalize to completed, got: \(updated)")
        let relisted = await exec.execute(WebToolCall(name: "task_list", arguments: [:]))
        #expect(relisted.contains("completed"))
    }

    @Test func taskUpdateMissingIdErrorsHonestly() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(
            WebToolCall(name: "task_update", arguments: ["id": "nope", "status": "done"]))
        #expect(result.contains("error"))
        #expect(result.contains("task_list"))
    }

    @Test func taskCreateRequiresContent() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "task_create", arguments: [:]))
        #expect(result.contains("error"))
    }

    // MARK: - web_fetch helpers (pure) + stubbed fetch

    @Test func fetchURLValidation() {
        #expect(ProjectWebToolExecutor.validatedFetchURL("https://example.com/x") != nil)
        #expect(ProjectWebToolExecutor.validatedFetchURL("http://localhost:8080/") != nil)
        #expect(ProjectWebToolExecutor.validatedFetchURL("file:///etc/passwd") == nil)
        #expect(ProjectWebToolExecutor.validatedFetchURL("ftp://x/y") == nil)
        #expect(ProjectWebToolExecutor.validatedFetchURL("javascript:alert(1)") == nil)
        #expect(ProjectWebToolExecutor.validatedFetchURL("not a url") == nil)
    }

    @Test func htmlStripsToReadableText() {
        let html = """
        <html><head><title>T</title><style>.x{}</style><script>var a=1;</script></head>
        <body><h1>Hi</h1><p>Hello <b>world</b> &amp; bye</p><br>tail</body></html>
        """
        let text = ProjectWebToolExecutor.stripHTMLToText(html)
        #expect(!text.contains("<"))
        #expect(!text.contains("var a=1"))
        #expect(text.contains("Hi"))
        #expect(text.contains("Hello"))
        #expect(text.contains("&"))
        #expect(!text.contains("&amp;"))
    }

    @Test func fetchTruncationMarksCut() {
        let text = String(repeating: "x", count: 100)
        #expect(ProjectWebToolExecutor.truncateFetch(text, limit: nil).count == 100)
        let cut = ProjectWebToolExecutor.truncateFetch(text, limit: 10)
        #expect(cut.contains("truncated"))
        #expect(cut.hasPrefix("xxxxxxxxxx"))
    }

    @Test func webFetchRejectsBadURLWithoutNetwork() async throws {
        let root = try makeTempRoot(prefix: "mimo-parity")
        let exec = ProjectWebToolExecutor(projectRoot: root.path, accessLevel: .fullAccess)
        let result = await exec.execute(WebToolCall(name: "WebFetch", arguments: ["url": "file:///etc/passwd"]))
        #expect(result.contains("error"))
        #expect(result.contains("http"))
    }
}
