import Foundation

extension WebToolProtocolEmulator {
    /// Map a model's informal tool spelling to the canonical tool name.
    /// Web models write "LS"/"ls" for list_dir, "Read" for read_file, etc.
    /// Unknown names → nil so they surface as `.unknownTool` validation errors
    /// instead of being silently dropped.
    ///
    /// Normalization (applied before matching): trim, lowercase, "-" → "_".
    /// This covers Anthropic PascalCase (Read/Edit/Write/Bash/Glob/Grep/Task/
    /// TodoWrite/WebFetch/Skill/TaskCreate/...), snake_case, and hyphenated
    /// spellings (git-commit, read-file) with one rule instead of N entries.
    static func canonicalToolName(_ name: String) -> String? {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch lower {
        case "ls", "list_dir", "list", "dir", "directory", "ls_dir":
            return WebEmulatedTool.listDir.rawValue
        case "read_file", "read", "cat", "view":
            return WebEmulatedTool.readFile.rawValue
        case "write_file", "write", "create", "create_file":
            return WebEmulatedTool.writeFile.rawValue
        case "edit_file", "edit", "replace", "apply_patch", "str_replace":
            return WebEmulatedTool.editFile.rawValue
        case "grep", "search", "find", "rg", "ripgrep":
            return WebEmulatedTool.grep.rawValue
        case "run_command", "run", "execute", "execute_command", "shell",
             "sh", "bash", "cmd":
            return WebEmulatedTool.runCommand.rawValue
        // Git operations
        case "git_status", "status", "gs":
            return WebEmulatedTool.gitStatus.rawValue
        case "git_diff", "diff", "gd":
            return WebEmulatedTool.gitDiff.rawValue
        case "git_log", "log":
            return WebEmulatedTool.gitLog.rawValue
        case "git_branch", "branch", "gb":
            return WebEmulatedTool.gitBranch.rawValue
        case "git_checkout", "checkout", "co", "gco":
            return WebEmulatedTool.gitCheckout.rawValue
        case "git_commit", "commit", "gc":
            return WebEmulatedTool.gitCommit.rawValue
        case "git_push", "push", "gp":
            return WebEmulatedTool.gitPush.rawValue
        case "git_pull", "pull", "gl":
            return WebEmulatedTool.gitPull.rawValue
        // File search & glob
        case "glob", "glob_search", "find_files":
            return WebEmulatedTool.glob.rawValue
        case "code_search", "codesearch", "search_code", "find_symbol", "symbol_search":
            return WebEmulatedTool.codeSearch.rawValue
        case "read_symbol", "readsymbol", "symbol_read", "read_definition", "go_to_definition":
            return WebEmulatedTool.readSymbol.rawValue
        // Real language-server operations (diagnostics/navigation).
        case "lsp", "language_server", "language_server_lsp", "langserver", "lsp_tool":
            return WebEmulatedTool.lsp.rawValue
        case "todo_read", "todos", "todo", "todoread", "read_todos", "plan", "plan_read", "current_plan":
            return WebEmulatedTool.todoRead.rawValue
        case "todo_write", "todowrite", "write_todos", "set_todos":
            return WebEmulatedTool.todoWrite.rawValue
        // Granular todo aliases: they edit ONE item, they never replace the
        // whole list (that is what todo_write does).
        case "todo_add", "add_todo", "todo_create", "new_todo":
            return WebEmulatedTool.taskCreate.rawValue
        case "todo_update", "update_todo", "todo_edit", "edit_todo", "todo_set_status":
            return WebEmulatedTool.taskUpdate.rawValue
        // Sub-agent / task tool
        case "task", "subagent", "agent", "spawn":
            return WebEmulatedTool.task.rawValue
        // Web fetch (Claude Code WebFetch parity)
        case "web_fetch", "webfetch", "fetch", "web_fetch_url", "fetch_url":
            return WebEmulatedTool.webFetch.rawValue
        // Advanced browser fetch (AntiBrowser REST engine)
        case "browser_fetch", "browserfetch", "browse", "browser", "open_url",
             "browser_open", "web_browse", "dom_fetch", "visit", "open_web_page":
            return WebEmulatedTool.browserFetch.rawValue
        // Installed skills (Claude Code Skill parity)
        case "skill", "use_skill", "load_skill", "skills":
            return WebEmulatedTool.skill.rawValue
        // Granular task tools (Claude Code TaskCreate/List/Update parity)
        case "task_create", "taskcreate", "create_task", "add_task", "new_task":
            return WebEmulatedTool.taskCreate.rawValue
        case "task_list", "tasklist", "list_tasks", "tasks", "list_todos", "todo_list", "todolist":
            return WebEmulatedTool.taskList.rawValue
        case "task_update", "taskupdate", "update_task", "edit_task", "complete_task":
            return WebEmulatedTool.taskUpdate.rawValue
        default:
            return nil
        }
    }

    /// Normalize a model's argument spellings to this tool's canonical keys.
    /// Different model families write `file_path`, `old_string`, `cmd`, etc.
    /// Canonical keys always win; unknown keys pass through untouched.
    static func normalizedArguments(for tool: WebEmulatedTool,
                                    from args: [String: String]) -> [String: String] {
        // Canonical key -> accepted spellings (canonical first).
        let table: [String: [String]]
        switch tool {
        case .readFile, .listDir:
            table = ["path": ["path", "file_path", "filepath", "file", "filename",
                              "target_file", "target", "dir", "directory", "folder", "location"]]
        case .editFile:
            table = ["path": ["path", "file_path", "filepath", "file", "filename", "target_file"],
                     "old": ["old", "old_string", "oldstring", "old_str", "old_text", "search", "find"],
                     "new": ["new", "new_string", "newstring", "new_str", "new_text", "replace", "replacement", "replace_with"]]
        case .grep:
            table = ["pattern": ["pattern", "regex", "regexp", "query", "search_pattern", "text"],
                     "path": ["path", "dir", "directory", "folder", "location", "file_path", "filepath", "file"]]
        case .glob:
            table = ["pattern": ["pattern", "glob_pattern", "glob", "files", "file_pattern", "query"],
                     "path": ["path", "dir", "directory", "folder", "location"]]
        case .codeSearch:
            table = ["query": ["query", "q", "symbol", "name", "text", "search", "term", "pattern"],
                     "limit": ["limit", "max", "count", "max_results"]]
        case .readSymbol:
            table = ["id": ["id", "symbol_id", "node_id", "symbolid"],
                     "path": ["path", "file_path", "filepath", "file", "filename"],
                     "name": ["name", "symbol", "function", "type", "declaration"],
                     "line": ["line", "start_line", "startline"]]
        case .lsp:
            table = ["operation": ["operation", "op", "action", "method"],
                     "path": ["path", "file_path", "filepath", "file", "filename"],
                     "line": ["line", "start_line", "startline"],
                     "column": ["column", "col", "character", "char"]]
        case .runCommand:
            table = ["command": ["command", "cmd", "cmdline", "bash_command", "shell_command", "command_line", "script"]]
        case .gitBranch, .gitCheckout:
            table = ["branch": ["branch", "branch_name", "new_branch", "target_branch", "ref"],
                     "create": ["create"]]
        case .gitCommit:
            table = ["message": ["message", "commit_message", "msg", "commit_msg", "title"],
                     "addAll": ["addAll", "add_all", "all"]]
        case .gitPush, .gitPull:
            table = ["remote": ["remote", "remote_name"],
                     "branch": ["branch", "branch_name", "ref"]]
        case .gitLog:
            table = ["limit": ["limit", "max_count", "n", "count"],
                     "path": ["path"]]
        case .gitDiff:
            table = ["staged": ["staged"], "path": ["path"]]
        case .gitStatus:
            table = ["path": ["path"]]
        case .todoWrite:
            table = ["todos": ["todos", "tasks", "items", "todo_list"]]
        case .taskCreate:
            table = ["content": ["content", "text", "task", "title", "description", "name", "todo"],
                     "status": ["status", "state"]]
        case .taskUpdate:
            table = ["id": ["id", "task_id", "todo_id"],
                     "content": ["content", "text", "task", "title", "description", "name", "todo"],
                     "status": ["status", "state"]]
        case .webFetch:
            table = ["url": ["url", "link", "uri", "href", "address", "website", "page"],
                     "limit": ["limit", "max_chars", "maxchars", "max_length", "chars"]]
        case .browserFetch:
            table = ["url": ["url", "target_url", "page_url", "address", "link", "uri", "href"],
                     "selector": ["selector", "css_selector", "query", "q", "element", "read_selector", "dom_selector"],
                     "script": ["script", "js", "javascript", "expression", "code", "evaluate"],
                     "click": ["click", "click_selector", "target", "button", "link_selector", "href"],
                     "screenshot": ["screenshot", "shot", "capture", "snapshot", "image"],
                     "limit": ["limit", "max_chars", "maxchars", "max_length", "chars", "max"]]
        case .skill:
            table = ["name": ["name", "skill", "skill_name", "skill_id", "id"]]
        case .todoRead, .taskList, .task:
            // No canonical keys to normalize (free-form or empty args) —
            // pass through untouched.
            return args
        case .writeFile:
            table = ["path": ["path", "file_path", "filepath", "file", "filename", "target_file"],
                     "content": ["content", "text", "data", "body", "contents", "new_content"]]
        }
        // Lowercased lookup so FILE_PATH and FilePath also match.
        let lowered: [(String, String)] = args.map {
            ($0.key.lowercased().replacingOccurrences(of: "-", with: "_"), $0.value)
        }
        var out: [String: String] = [:]
        for (canonical, variants) in table {
            for key in [canonical] + variants {
                if let match = lowered.first(where: { $0.0 == key }) {
                    out[canonical] = match.1
                    break
                }
            }
        }
        // Pass through anything unmapped (limit, offset, staged, flags):
        // normalization must never drop arguments the tool needs.
        let taken = Set(out.keys.map { $0.lowercased() })
        for (key, value) in args where !taken.contains(key.lowercased()) {
            out[key] = value
        }
        return out
    }

    /// Resolve a call to its canonical tool name (aliases → canonical).
    /// Unknown names pass through unchanged so validation still reports the
    /// model's original spelling in `.unknownTool` errors. Every consumer
    /// that switches on tool identity (gate, validate, executor) must use
    /// the resolved call — otherwise an alias like "Bash" would bypass the
    /// run_command approval gate by falling into `.none`.
    static func canonicalized(_ call: WebToolCall) -> WebToolCall {
        guard let canonical = canonicalToolName(call.name),
              canonical != call.name else {
            return call
        }
        return WebToolCall(name: canonical, arguments: call.arguments)
    }

    static func parseSingleCall(_ jsonString: String) -> WebToolCall? {
        // Audit 2026-09-08 (Qwen live): reasoning models emit NBSP (\\u{00A0})
        // instead of plain spaces inside the JSON body and can break the
        // fence into 'tool\\n1\\n{...}' — normalize both away before parsing.
        let normalized = jsonString
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        if let call = decodeSingleCall(normalized) {
            return call
        }
        guard let repaired = repairedJSONObject(normalized) else { return nil }
        return decodeSingleCall(repaired)
    }

    static func decodeSingleCall(_ jsonString: String) -> WebToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String else {
            return nil
        }
        var args: [String: String] = [:]
        if let rawArgs = obj["args"] as? [String: Any] {
            for (k, v) in rawArgs {
                args[k] = jsonScalarString(v)
            }
        } else if let rawArgs = obj["arguments"] as? [String: Any] {
            for (k, v) in rawArgs {
                args[k] = jsonScalarString(v)
            }
        } else if let rawArgs = obj["arguments"] as? String {
            // Llama 3.1 / OpenAI verbose: arguments приходят JSON-СТРОКОЙ —
            // {"name": "grep", "arguments": "{\"pattern\": \"x\"}"}.
            if let data = rawArgs.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    args[k] = jsonScalarString(v)
                }
            }
        }
        return WebToolCall(name: name, arguments: args)
    }

    /// Recover a model-emitted tool-call body whose JSON is structurally
    /// damaged in a way that preserves intent. Live 2026-10-25: a model emitted
    /// a 16 KB `write_file` body and forgot the final `}` of the outer object —
    /// the host silently dropped the call, the model kept apologizing that
    /// "the system is not executing it". Two damage classes are repaired:
    /// raw control characters inside strings (a literal newline instead of
    /// \\n) and missing closing brackets at the very end. An unterminated
    /// string is NOT repaired — the content itself would be truncated, so the
    /// caller falls back to the truncated-stub path instead.
    static func repairedJSONObject(_ text: String) -> String? {
        var out = ""
        var stack: [Character] = []
        var inString = false
        var escaped = false
        var modified = false
        for ch in text {
            if inString {
                if escaped {
                    out.append(ch)
                    escaped = false
                } else if ch == "\\" {
                    out.append(ch)
                    escaped = true
                } else if ch == "\"" {
                    out.append(ch)
                    inString = false
                } else if ch == "\n" {
                    out.append("\\n")
                    modified = true
                } else if ch == "\r" {
                    out.append("\\r")
                    modified = true
                } else if ch == "\t" {
                    out.append("\\t")
                    modified = true
                } else if let scalar = ch.unicodeScalars.first, scalar.value < 0x20 {
                    out.append("\\u\(String(format: "%04x", scalar.value))")
                    modified = true
                } else {
                    out.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inString = true
                    out.append(ch)
                case "{":
                    stack.append("}")
                    out.append(ch)
                case "[":
                    stack.append("]")
                    out.append(ch)
                case "}", "]":
                    if !stack.isEmpty { stack.removeLast() }
                    out.append(ch)
                default:
                    out.append(ch)
                }
            }
        }
        guard !inString, !escaped else { return nil }
        if !stack.isEmpty {
            out.append(contentsOf: stack.reversed())
            modified = true
        }
        guard modified else { return nil }
        return out
    }
}
