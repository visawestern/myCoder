import Foundation

/// One tool call requested by a web model through the emulated text protocol
/// (plan Раздел 12 Блок 2 п.8/п.13).
struct WebToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}

/// A tool block the model emitted that could not become an executable call.
/// The driver feeds it back as a `tool_result` error instead of dropping it,
/// so one malformed call never stalls the turn.
struct WebToolCallParseIssue: Equatable {
    /// The tool name recovered from the broken block, or "tool" when unknown.
    let toolName: String
    /// What exactly is wrong with the block (unclosed brace, unterminated
    /// string, unknown tool name, ...).
    let reason: String
    /// The offending block, truncated for logs and feedback.
    let raw: String
}

/// The set of tools we teach a plain web chat to "call" so it behaves like a
/// real coding agent (plan Блок 2 п.12). These map 1:1 to the app's real
/// tool executors (read_file/write_file/etc.).
enum WebEmulatedTool: String, CaseIterable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case editFile = "edit_file"
    case listDir = "list_dir"
    case grep = "grep"
    case runCommand = "run_command"
    // Git operations
    case gitStatus = "git_status"
    case gitDiff = "git_diff"
    case gitLog = "git_log"
    case gitBranch = "git_branch"
    case gitCheckout = "git_checkout"
    case gitCommit = "git_commit"
    case gitPush = "git_push"
    case gitPull = "git_pull"
    // File search & glob
    case glob = "glob"
    // Project code graph (symbols + edges), built by the host from source.
    case codeSearch = "code_search"
    case readSymbol = "read_symbol"
    // Language-server intelligence (diagnostics, definition, references,
    // hover, completion) from the real LSP servers enabled in Settings.
    case lsp = "lsp"
    case todoRead = "todo_read"
    case todoWrite = "todo_write"
    // Sub-agent / task tool
    case task = "task"
    // Web fetch (Claude Code WebFetch parity)
    case webFetch = "web_fetch"
    // Advanced browser fetch: full DOM access (script), selector reads, link
    // clicks and screenshots through the AntiBrowser REST engine.
    case browserFetch = "browser_fetch"
    // Installed skill lookup (Claude Code Skill parity)
    case skill = "skill"
    // Granular task tools (Claude Code TaskCreate/List/Update parity),
    // backed by the same todo store as todo_read/todo_write.
    case taskCreate = "task_create"
    case taskList = "task_list"
    case taskUpdate = "task_update"

    var argumentSchema: String {
        switch self {
        case .readFile: return #"{"path": "<relative path>", "limit": "<optional max lines>", "offset": "<optional 1-based first line>"}"#
        case .writeFile: return #"{"path": "<relative path>", "content": "<file content>"}"#
        case .editFile: return #"{"path": "<relative path>", "old": "<text>", "new": "<text>"}"#
        case .listDir: return #"{"path": "<relative path>"}"#
        case .grep: return #"{"pattern": "<regex>", "path": "<relative path>"}"#
        case .runCommand: return #"{"command": "<shell command>"}"#
        case .gitStatus: return #"{"path": "<relative path>"}"#
        case .gitDiff: return #"{"path": "<relative path>", "staged": <bool>}"#
        case .gitLog: return #"{"path": "<relative path>", "limit": <int>}"#
        case .gitBranch: return #"{"branch": "<branch name>", "create": <bool>}"#
        case .gitCheckout: return #"{"branch": "<branch name>"}"#
        case .gitCommit: return #"{"message": "<commit message>", "addAll": <bool>}"#
        case .gitPush: return #"{"remote": "<remote name>", "branch": "<branch name>"}"#
        case .gitPull: return #"{"remote": "<remote name>", "branch": "<branch name>"}"#
        case .glob: return #"{"pattern": "<glob pattern>", "path": "<relative path>"}"#
        case .codeSearch: return #"{"query": "<symbol name or code text>", "limit": "<optional max hits>"}"#
        case .readSymbol: return #"{"id": "<code_search id>", "path": "...", "name": "...", "line": 1}"#
        case .lsp: return #"{"operation": "diagnostics|definition|references|hover|completion", "path": "...", "line": 1}"#
        case .todoRead: return #"{}"#
        case .todoWrite: return #"{"todos": [{"id": "<id>", "content": "<text>", "status": "<pending|in_progress|completed>"}]}"#
        case .task: return #"{"description": "<task description>", "prompt": "<detailed prompt>", "subagentType": "<general|code|debug|review>"}"#
        case .webFetch: return #"{"url": "<http(s) URL>", "limit": "<optional max chars>"}"#
        case .browserFetch: return #"{"url": "<http(s) URL>", "selector": "<CSS>", "script": "<JS>", "click": "<CSS>", "screenshot": "<1/true>", "limit": "<max chars>"}"#
        case .skill: return #"{"name": "<installed skill id> (omit to list installed skills)"}"#
        case .taskCreate: return #"{"content": "<task text>", "status": "<optional pending|in_progress|completed>"}"#
        case .taskList: return #"{}"#
        case .taskUpdate: return #"{"id": "<todo id or plan task id>", "content": "<optional new text>", "status": "<optional pending|in_progress|completed>"}"#
        }
    }

    var description: String {
        switch self {
        case .readFile: return "Read a file's contents. Page large files with 'limit' (max lines) + 'offset' (1-based first line)."
        case .writeFile: return "Create or overwrite a file."
        case .editFile: return "Replace an exact substring in a file."
        case .listDir: return "List entries of a directory."
        case .grep: return "Search files for a regex pattern."
        case .runCommand: return "Run a shell command (requires approval)."
        case .gitStatus: return "Show git status (modified, staged, untracked files)."
        case .gitDiff: return "Show git diff (staged or unstaged)."
        case .gitLog: return "Show git commit history."
        case .gitBranch: return "List or create git branches."
        case .gitCheckout: return "Switch git branch."
        case .gitCommit: return "Create a git commit."
        case .gitPush: return "Push commits to remote."
        case .gitPull: return "Pull commits from remote."
        case .glob: return "Find files matching a glob pattern."
        case .codeSearch: return "Search the project code graph for functions, types and variables; returns exact line ranges and graph neighbors."
        case .readSymbol: return "Read one indexed symbol by id (or path + name) with its exact line range; refuses stale line numbers."
        case .lsp: return "Ask the real language server about a file: diagnostics (errors/warnings), definition, references, hover or completion at a 1-based line/column."
        case .todoRead: return "Read the current execution plan and todo checklist."
        case .todoWrite: return "Write/update the todo checklist (replaces the whole list)."
        case .task: return "Launch a sub-agent for a complex task (runs in background, returns result)."
        case .webFetch: return "Fetch a web page as text (http/https only, bounded)."
        case .browserFetch: return "Fetch a web page through the browser engine: navigate, optionally click a selector, then return page text (or a CSS selector's text, or a JS expression result) and optionally a screenshot. Full DOM access via 'script'."
        case .skill: return "Show an installed skill's instructions (omit name to list skills)."
        case .taskCreate: return "Add one task to the checklist."
        case .taskList: return "List checklist tasks."
        case .taskUpdate: return "Update one checklist task by id."
        }
    }

    /// Harness-tax C2: the always-loaded core. Five tools cover the
    /// read→edit→verify loop; everything else loads on request so the
    /// initial context stays small (Pi-style minimal profile).
    var isCore: Bool {
        switch self {
        case .readFile, .writeFile, .editFile, .listDir, .runCommand:
            return true
        default:
            return false
        }
    }
}

/// Harness-tax C2: which tools ship inline in the preamble per profile.
/// `unknown` (legacy rows) behaves like `full` — no behavior change for
/// existing callers until a profile is explicitly chosen (C4).
extension HarnessProfile {
    var tools: [WebEmulatedTool] {
        switch self {
        case .minimal:
            return WebEmulatedTool.allCases.filter { $0.isCore }
        case .standard:
            let extra: Set<String> = [
                "grep", "glob", "git_status", "git_diff", "todo_read", "todo_write",
                "code_search", "read_symbol"
            ]
            return WebEmulatedTool.allCases.filter { $0.isCore || extra.contains($0.rawValue) }
        case .full, .unknown:
            return WebEmulatedTool.allCases
        }
    }
}

/// Emulates a tool-calling protocol over a plain web chat that has no native
/// tool support (plan Раздел 12 Блок 2). The model is instructed via a system
/// preamble to emit strict ```tool blocks; we parse them, execute locally, and
/// feed ```tool_result back so it continues — an agentic loop over web chat.
enum WebToolProtocolEmulator {

    /// System preamble teaching the model the strict tool-call format.
    /// Mirrors the OpenCode (anomalyco/opencode) system-prompt structure: an
    /// identity + role line, environment context (working directory, git, date),
    /// a tool-usage policy, the exact tool-call wire format, and the full tool
    /// list. Web chat has no native tool API, so the host emulates one and the
    /// model must announce each tool call in a parseable block.
    ///
    /// Harness-tax C2: `profile` selects how many tools ship inline —
    /// `.minimal` lists only the 5 core tools and names the rest on one
    /// "available on request" line (their schemas follow when asked).
    /// `nil` (default) preserves the legacy full-list behavior exactly.
    /// `budgetBytes` caps the total size by truncating the tail of
    /// `userSystemPrompt` (marked); the wire format is never cut.
    static func systemPreamble(tools: [WebEmulatedTool] = WebEmulatedTool.allCases,
                               userSystemPrompt: String = "",
                               projectRoot: String = "",
                               directory: String = "",
                               isGitRepo: Bool = false,
                               date: Date = Date(),
                               profile: HarnessProfile? = nil,
                               budgetBytes: Int? = nil) -> String {
        // Audit 2026-09-08 (Kimi): vendors convert pastes over ~4000 bytes
        // into .txt attachments, and free web models answer each split part
        // instead of honoring the continuation header — so the preamble MUST
        // ship as ONE message under 3900 bytes. Compact form, same wire
        // protocol (```tool blocks + tool_result feedback).
        let listed = profile.map { $0.tools } ?? tools
        let listedNames = Set(listed.map(\.rawValue))
        let onRequest = WebEmulatedTool.allCases.filter { !listedNames.contains($0.rawValue) }
        var prompt = userSystemPrompt
        if let budget = budgetBytes {
            // Reserve room for everything except the user prompt: build once
            // without it, then fit the tail of the prompt into the remainder.
            let base = buildPreambleLines(userSystemPrompt: "", projectRoot: projectRoot,
                                          directory: directory, isGitRepo: isGitRepo, date: date,
                                          listed: listed, onRequest: onRequest)
                .joined(separator: "\n").utf8.count
            let room = max(0, budget - base)
            if prompt.utf8.count > room {
                var cut = prompt
                let target = max(0, room - 14)
                while cut.utf8.count > target && !cut.isEmpty {
                    cut.removeLast(max(1, (cut.utf8.count - target) / 2))
                }
                prompt = cut + "\n[truncated]"
            }
        }
        return buildPreambleLines(userSystemPrompt: prompt, projectRoot: projectRoot,
                                  directory: directory, isGitRepo: isGitRepo, date: date,
                                  listed: listed, onRequest: onRequest)
            .joined(separator: "\n")
    }

    private static func buildPreambleLines(userSystemPrompt: String,
                                           projectRoot: String,
                                           directory: String,
                                           isGitRepo: Bool,
                                           date: Date,
                                           listed: [WebEmulatedTool],
                                           onRequest: [WebEmulatedTool]) -> [String] {
        var lines: [String] = []
        if !userSystemPrompt.isEmpty {
            lines.append(userSystemPrompt)
            lines.append("")
        }
        if onRequest.isEmpty {
            // Full-profile identity: compact but keeps every live-proven
            // refusal guard (role, bridge, not-sandboxed, verify-with-
            // list_dir, never-claim-ran). The old long form pushed the
            // first-turn preamble over the vendor paste budget (Kimi ~4000B)
            // and split the tool contract into continuation parts (user
            // report 2026-10-30 — prompt chunked at 4047B).
            lines.append("You are Claude Code, the agentic coding assistant, running in the user's project through a tool bridge. The host runs every tool block you emit locally and returns the result — you are NOT sandboxed, never claim missing file access (verify with one list_dir block instead of refusing). Never claim a tool ran before you see its result.")
        } else {
            // Harness-tax C4: compact identity for slim profiles. Keeps every
            // live-proven refusal guard (role, bridge, not-sandboxed,
            // verify-with-list_dir, never-claim-ran) at ~40% of the bytes.
            lines.append("You are the agentic coding assistant in the user's project. The host runs every tool block you emit locally and returns the result — you are NOT sandboxed, never claim missing file access (verify with one list_dir block instead of refusing). Never claim a tool ran before you see its result.")
        }
        let dir = directory.isEmpty ? (projectRoot.isEmpty ? "." : projectRoot) : directory
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        lines.append("cwd: \(dir) · git: \(isGitRepo ? "yes" : "no") · date: \(fmt.string(from: date))")
        lines.append("Invoke a tool by replying with ONE form, then WAIT for the ```tool_result:")
        lines.append("```tool")
        lines.append(#"{"name": "<tool_name>", "args": { ... }}"#)
        lines.append("```")
        lines.append("or XML form: <tool_name>key1=value1 key2=value2</tool_name>")
        // Audit 2026-09-09 (ChatGPT/Claude live): an abstract "<tool_name>"
        // example alone lets models narrate refusal ("no list_dir in my
        // tools") instead of emitting. A concrete minimal example plus an
        // explicit no-narration rule makes them emit the block (live: Claude
        // emitted list_dir verbatim after the same demand).
        lines.append("Concrete example (list the working directory):")
        lines.append("```tool")
        lines.append(#"{"name": "list_dir", "args": {"path": "."}}"#)
        lines.append("```")
        lines.append("Rules: every listed tool above IS available — never say a tool is missing or unavailable, never refuse as a sandboxed model, never narrate tool use, never invent results. Emit a tool block when a task needs one, then wait for its result.")
        lines.append("Paths outside the project are not yours to judge: emit the tool call with the absolute path and let the host decide. It asks the user for access and then runs the call, or returns a validation error — never refuse a task because a path is outside the working directory.")
        let listedNames2 = Set(listed.map(\.rawValue))
        let inspectors = ["read_file", "list_dir", "grep", "glob"].filter { listedNames2.contains($0) }
        var policy = "Policy: inspect first (\(inspectors.joined(separator: "/")))"
        if listedNames2.contains("write_file") || listedNames2.contains("edit_file") {
            policy += "; write via write_file/edit_file"
        }
        if listedNames2.contains("run_command") {
            policy += "; run_command only at full access (read-only prints like cat/grep/sed -n/git log run without approval)"
        }
        if listedNames2.contains("git_status") {
            policy += "; git_* for VCS"
        }
        if listedNames2.contains("todo_read") {
            policy += "; todo_* for the checklist (todo_read also shows the plan)"
        }
        policy += ". Page large files with read_file offset/limit. When done, reply without a tool block."
        lines.append(policy)
        lines.append("Tools:")
        for tool in listed {
            lines.append("- \(tool.rawValue) args: \(tool.argumentSchema)")
        }
        if !onRequest.isEmpty {
            lines.append("Further tools available on request (name one and its schema follows): \(onRequest.map(\.rawValue).joined(separator: ", ")).")
        }
        return lines
    }


}

enum WebToolValidationError: Error, Equatable {
    case pathEscapesProject(String)
    case unknownTool(String)
    case incompleteJSON
}
