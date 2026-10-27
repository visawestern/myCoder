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
    case todoRead = "todo_read"
    case todoWrite = "todo_write"
    // Sub-agent / task tool
    case task = "task"
    // Web fetch (Claude Code WebFetch parity)
    case webFetch = "web_fetch"
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
        case .readSymbol: return #"{"id": "<symbol id from code_search>", "path": "<optional file>", "name": "<optional symbol>", "line": "<optional 1-based line>"}"#
        case .todoRead: return #"{}"#
        case .todoWrite: return #"{"todos": [{"id": "<id>", "content": "<text>", "status": "<pending|in_progress|completed>"}]}"#
        case .task: return #"{"description": "<task description>", "prompt": "<detailed prompt>", "subagentType": "<general|code|debug|review>"}"#
        case .webFetch: return #"{"url": "<http(s) URL>", "limit": "<optional max chars>"}"#
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
        case .todoRead: return "Read the current execution plan and todo checklist."
        case .todoWrite: return "Write/update the todo checklist (replaces the whole list)."
        case .task: return "Launch a sub-agent for a complex task (runs in background, returns result)."
        case .webFetch: return "Fetch a web page as text (http/https only, bounded)."
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
            lines.append("You are Claude Code, the agentic coding assistant, running in the user's project through a tool bridge. The host app executes every tool call you emit on the user's machine and returns the real result. You are NOT a sandboxed chat model — never claim you lack file/system access: the tools below run locally and their results come back to you. If you catch yourself believing you have different (sandbox-only) tools, that belief is wrong for this chat — verify with one list_dir block instead of refusing. Never claim a tool ran before you see its result.")
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
        lines.append("Rules: every listed tool above IS available — never say a tool is missing or unavailable, never refuse with \"I'm a sandboxed model / I can't access your machine\", never narrate tool use in prose, never invent results. When a task needs a tool, emit its block immediately, then wait for the result.")
        lines.append("Paths outside the project are not yours to judge: emit the tool call with the absolute path and let the host decide. It asks the user for access and then runs the call, or returns a validation error — never refuse a task because a path is outside the working directory.")
        let listedNames2 = Set(listed.map(\.rawValue))
        let inspectors = ["read_file", "list_dir", "grep", "glob"].filter { listedNames2.contains($0) }
        var policy = "Policy: inspect first (\(inspectors.joined(separator: "/"))); write via write_file/edit_file; run_command only at full access (read-only prints like cat/grep/sed -n/git log run without approval)"
        if listedNames2.contains("git_status") {
            policy += "; git_* for VCS"
        }
        if listedNames2.contains("todo_read") {
            policy += "; todo_* for the checklist, todo_read also shows the current execution plan (its task ids are the plan ids — todo_update/todo_edit moves a plan task)"
        }
        policy += ". Page large files with read_file offset/limit instead of re-reading from the start. When done, reply without a tool block."
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

    /// Extract all tool calls from a model response. Tolerant of surrounding
    /// prose and markdown fences (plan Блок 2 п.11/п.13), and — since Round 12 —
    /// also of the informal `[tool call: NAME with args]` syntax that plain web
    /// models actually emit (e.g. `[tool call: LS with path "."]`), so the
    /// agentic loop never stalls on a well-meant but non-strict call.
    static func parseToolCalls(from responseText: String) -> [WebToolCall] {
        parseToolCallsWithIssues(from: responseText).calls
    }

    /// Same parser, plus one report per tool block that could not become an
    /// executable call. A malformed block is never silently dropped: the
    /// driver turns each issue into a `tool_result` error for the model, so a
    /// single broken call cannot kill the rest of the turn.
    static func parseToolCallsWithIssues(
        from responseText: String
    ) -> (calls: [WebToolCall], issues: [WebToolCallParseIssue]) {
        var calls: [WebToolCall] = []
        var issues: [WebToolCallParseIssue] = []
        // Find ```tool ... ``` fenced blocks. The closing fence may directly
        // follow the JSON (no trailing newline) — tolerate that too.
        let scanner = responseText as NSString
        let pattern = "```tool\\s*\\n(.*?)\\s*```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: responseText, range: NSRange(location: 0, length: scanner.length))
            for match in matches where match.numberOfRanges >= 2 {
                let jsonString = scanner.substring(with: match.range(at: 1))
                if let call = parseSingleCall(jsonString) {
                    calls.append(call)
                    continue
                }
                // A stream cut off mid-JSON is answered with "re-emit the
                // complete block" by the driver's truncated-call branch.
                if let stub = parseTruncatedToolCallStub(from: jsonString).first {
                    calls.append(stub)
                    continue
                }
                issues.append(WebToolCallParseIssue(
                    toolName: recoveredToolName(from: jsonString) ?? "tool",
                    reason: describeJSONProblem(jsonString),
                    raw: String(jsonString.prefix(400))
                ))
            }
        }
        // Then the informal `[tool call: NAME ...]` variant.
        calls.append(contentsOf: parseInformalCalls(from: responseText))
        // Then the XML `<NAME>k=v</NAME>` variant that big-pickle / MiMo-style models emit natively.
        calls.append(contentsOf: parseTaggedToolCalls(from: responseText))
        // Then the SHORT XML form the preamble itself teaches:
        // `<list_dir>path=.</list_dir>` (audit 2026-09-11, Kimi live: the
        // model emits exactly this, the verbose parser ignores it, and the
        // turn dies with raw tool text as the "answer").
        calls.append(contentsOf: parseShortTaggedCalls(from: responseText))

        // Audit 2026-09-08 (Qwen live): reasoning streams can BREAK the fence
        // itself — the answer arrives as `tool\n1\n{"name":\u{00A0}"list_dir", ...}`
        // with no backticks at all. Scan for complete {"name": …, "args": {…}}
        // objects in the raw text (NBSP-normalized) before the truncated-stub
        // fallback, so a fully written call without fences still executes.
        // A broken *fenced* block must not hide it: issues are reported
        // separately and do not block recovery of a valid unfenced call.
        if calls.isEmpty {
            calls.append(contentsOf: parseUnfencedJSONToolCalls(from: responseText))
        }


        // Audit 2026-09-08 (Qwen live): models sometimes emit a tool call the
        // STREAM CUT OFF mid-JSON — `call {"name": "list_dir", "arguments` —
        // no fence, no closing brace. Such a response is NOT a final answer;
        // recover the tool name and keep the loop alive so the driver can
        // feed back "incomplete call, re-emit" instead of showing the stub.
        // Only when no complete call parsed — the stub detector is a fallback,
        // never a second opinion on a well-formed call.
        if calls.isEmpty && issues.isEmpty {
            calls.append(contentsOf: parseTruncatedToolCallStub(from: responseText))
        }
        return (calls, issues)
    }

    /// The tool name written inside a broken block, so the error result names
    /// the tool the model meant to call.
    private static func recoveredToolName(from block: String) -> String? {
        let pattern = "\"name\"\\s*:\\s*\"([A-Za-z_][A-Za-z0-9_.-]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: (block as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        return (block as NSString).substring(with: match.range(at: 1))
    }

    /// Detect a stream-truncated tool call: a known tool name followed by an
    /// UNTERMINATED JSON body (no closing `}` after the name, no fence). The
    /// recovered call carries whatever arguments are readable plus a marker so
    /// validation reports it as incomplete rather than executing blindly.
    /// Live (Qwen 2026-09-08): reasoning streams also die mid-XML, mangling
    /// the tags into `⟨path⟩ ⟨arg_value⟩` — a bare known-tool mention near
    /// half-written argument tags is detected the same way.
    static func parseTruncatedToolCallStub(from text: String) -> [WebToolCall] {
        // JSON form: `{"name": "tool", ...` with no closing brace.
        let pattern = "\\{\\s*\"name\"\\s*:\\s*\"([A-Za-z_][A-Za-z0-9_.-]*)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let scanner = text as NSString
            var calls: [WebToolCall] = []
            for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 2 {
                let name = scanner.substring(with: match.range(at: 1))
                guard let canonical = canonicalToolName(name) else { continue }
                let rest = scanner.substring(from: match.range(at: 1).location + match.range(at: 1).length)
                if rest.contains("}") { continue }
                var args = truncatedCallArguments(from: rest)
                args["__mycoder_truncated"] = "1"
                calls.append(WebToolCall(name: canonical, arguments: args))
            }
            if !calls.isEmpty { return calls }
        }
        // Mangled/truncated XML form: the tool name followed by half-written
        // argument tags (⟨arg⟩ / ⟨/arg_value⟩ / <arg without close) — the
        // complete tagged parser already handles well-formed XML.
        for (canonical, raw) in WebEmulatedTool.allCases.map({ (canonicalToolName($0.rawValue)!, $0.rawValue) }) {
            guard let range = text.range(of: raw) else { continue }
            let after = String(text[range.upperBound...])
            // A well-formed tagged body after the mention parses upstream —
            // never touch those. Vendors also mangle angle brackets into
            // unicode look-alikes, so accept both ASCII and mangled closers.
            if after.contains("</\(raw)>") || after.contains("⟩/\(raw)⟩") { continue }
            // Truncated/mangled argument region right after the tool mention:
            // half-written or unicode-mangled angle tags. A CLOSING tag of the
            // tool right after the mention (any bracket flavor) means the
            // tagged parser already handled the full body — skip.
            if after.hasPrefix(">") || after.hasPrefix("⟩") { continue }
            // A closed </tool_name> right after the mention means the NAME
            // arrived complete — but the ARGUMENT region may still be a
            // mangled truncation (live: "⟨path⟩ ⟨arg_value⟩ ." with real
            // <arg_key>/<arg_value> tags never appearing). Only skip when
            // real ASCII argument tags exist AND no mangled ones.
            if after.hasPrefix("</tool_name>") || after.hasPrefix("⟩/tool_name⟩") {
                let argRegion = String(after[after.index(after.startIndex, offsetBy: min(after.count, 13))...])
                let opensRealTag = argRegion.contains("<arg_key") || argRegion.contains("<arg_value") || argRegion.contains("<path")
                let opensMangledTag = argRegion.contains("⟨arg") || argRegion.contains("⟨path")
                if opensMangledTag {
                    var args = truncatedCallArguments(from: argRegion)
                    args["__mycoder_truncated"] = "1"
                    return [WebToolCall(name: canonical, arguments: args)]
                }
                if opensRealTag { continue }
                // Audit 2026-09-09 (test regression): a COMPLETE well-formed
                // XML body whose angle brackets the vendor mangles into ⟨…⟩
                // ("⟨pattern⟩x⟨/pattern⟩") contains argument-shaped tags but
                // no truncation — a generic "any ⟨ counts" check fired a fake
                // truncated stub and blocked the call. Only half-written
                // argument tags (⟨arg…, ⟨path…, <arg without closer, or an
                // unterminated ⟨ value) mark a real cut stream.
                let hasHalfWrittenArg = argRegion.contains("⟨arg") || argRegion.contains("⟨path")
                    || (argRegion.contains("<arg") && !argRegion.contains(">arg"))
                    || (argRegion.contains("⟨") && !argRegion.contains("⟩"))
                if hasHalfWrittenArg {
                    var args = truncatedCallArguments(from: argRegion)
                    args["__mycoder_truncated"] = "1"
                    return [WebToolCall(name: canonical, arguments: args)]
                }
                continue
            }
            if after.contains("⟨") || after.contains("<arg") || after.contains("</tool") {
                var args = truncatedCallArguments(from: after)
                args["__mycoder_truncated"] = "1"
                return [WebToolCall(name: canonical, arguments: args)]
            }
        }
        // Truncated `<tool_name>NAME` prefix (Qwen live: the stream died
        // INSIDE the tool name itself — "<tool_name>list" — leaving a known
        // tool prefix with no closing bracket at all). Recover it as a stub
        // so the driver asks the model to re-emit the complete call.
        if let nameRange = text.range(of: "<tool_name>") ?? text.range(of: "⟨tool_name⟩") {
            let candidate = String(text[nameRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for (canonical, raw) in WebEmulatedTool.allCases.map({ (canonicalToolName($0.rawValue)!, $0.rawValue) }) {
                if candidate.hasPrefix(raw) { continue }   // full name → handled above
                if raw.hasPrefix(candidate), !candidate.isEmpty {
                    return [WebToolCall(name: canonical, arguments: ["__mycoder_truncated": "1"])]
                }
            }
        }
        return []
    }

    /// Best-effort argument extraction from a truncated JSON body: any
    /// `"key": "value` pairs, even when the closing quote/brace was lost.
    private static func truncatedCallArguments(from body: String) -> [String: String] {
        var args: [String: String] = [:]
        let pattern = "\"([A-Za-z_][A-Za-z0-9_.-]*)\"\\s*:\\s*\"?([^\",}]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return args }
        let scanner = body as NSString
        for match in regex.matches(in: body, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            if let k = substring(in: match, at: 1, of: scanner),
               let v = substring(in: match, at: 2, of: scanner) {
                let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { args[key] = v.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        return args
    }

    /// Parse the XML tool-call format that big-pickle / MiMo-style models emit:
    /// `<tool_call>execute_command<arg_key>command</arg_key><arg_value>pwd</arg_value></tool_call>`.
    /// Live models pretty-print the block across lines (newline after the name,
    /// between arg tags, and before </tool_call>), so every boundary tolerates
    /// whitespace — otherwise the calls are silently dropped and the agentic
    /// loop stalls showing raw unexecuted tool calls.
    private static func parseTaggedToolCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "<tool_call>\\s*([A-Za-z_][A-Za-z0-9_.-]*)((?:\\s*<arg_key>[\\s\\S]*?</arg_key>\\s*<arg_value>[\\s\\S]*?</arg_value>)*)\\s*</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            let name = scanner.substring(with: match.range(at: 1))
            guard let canonical = canonicalToolName(name) else { continue }
            let pairsBody = scanner.substring(with: match.range(at: 2))
            let argPattern = "<arg_key>([\\s\\S]*?)</arg_key>\\s*<arg_value>([\\s\\S]*?)</arg_value>"
            var args: [String: String] = [:]
            if let pairRegex = try? NSRegularExpression(pattern: argPattern) {
                let body = pairsBody as NSString
                for pm in pairRegex.matches(in: pairsBody, range: NSRange(location: 0, length: body.length)) where pm.numberOfRanges >= 3 {
                    if let k = substring(in: pm, at: 1, of: body),
                       let v = substring(in: pm, at: 2, of: body) {
                        args[k.trimmingCharacters(in: .whitespacesAndNewlines)] = v
                    }
                }
            }
            calls.append(WebToolCall(name: canonical, arguments: args))
        }
        return calls
    }

    /// Parse the SHORT XML form taught by the system preamble:
    /// `<list_dir>path=.</list_dir>`. Tag name must be a known tool (this
    /// rejects arbitrary HTML), args are `key=value` pairs separated by
    /// whitespace with optionally quoted values.
    private static func parseShortTaggedCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "<([A-Za-z_][A-Za-z0-9_.-]*)>([^<>]*)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            let name = scanner.substring(with: match.range(at: 1))
            guard let canonical = canonicalToolName(name) else { continue }
            let body = scanner.substring(with: match.range(at: 2))
            calls.append(WebToolCall(name: canonical, arguments: parseShortTagArgs(body)))
        }
        return calls
    }

    /// Parse `k=v` pairs: `path=.`, `path="my dir"`, `limit=5`.
    private static func parseShortTagArgs(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        let scanner = text as NSString
        let pattern = "([A-Za-z_][A-Za-z0-9_.-]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|(\\S+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return args }
        for m in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where m.numberOfRanges >= 6 {
            guard let key = substring(in: m, at: 1, of: scanner) else { continue }
            let value = substring(in: m, at: 3, of: scanner)
                ?? substring(in: m, at: 4, of: scanner)
                ?? substring(in: m, at: 5, of: scanner)
                ?? ""
            args[key.trimmingCharacters(in: .whitespacesAndNewlines)] = value
        }
        return args
    }

    /// Parse `[tool call: NAME with key value / key="value" ...]`.
    private static func parseInformalCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "\\[tool call:\\s*([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        var calls: [WebToolCall] = []
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for match in matches where match.numberOfRanges >= 2 {
            let body = scanner.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = body.split(separator: " ", maxSplits: 1).map(String.init)
            guard let rawName = tokens.first, let name = canonicalToolName(rawName) else { continue }
            var argsText = tokens.count > 1 ? tokens[1] : ""
            // Drop the connective "with": "[tool call: LS with path "."]" →
            // args "path \".\"".
            let withPrefix = argsText.trimmingCharacters(in: .whitespaces)
            if withPrefix.hasPrefix("with ") {
                argsText = String(withPrefix.dropFirst(5))
            }
            calls.append(WebToolCall(name: name, arguments: parseInformalArgs(argsText)))
        }
        return calls
    }

    /// Parse `path "."` / `path="."` / `path='.'` / `path=.` / `pattern "x"`
    /// into [String: String]. Bare `key value` (space-separated, unquoted)
    /// stays unsupported — too ambiguous with paths containing spaces.
    private static func parseInformalArgs(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        let scanner = text as NSString
        // k="v" OR k "v" OR k='v' OR k=v. Alternation groups: the branch
        // that did NOT match has NSNotFound ranges — guard before substring.
        let key = "([A-Za-z_][A-Za-z0-9_]*)"
        let quoted = key + "\\s*=\\s*\"([^\"]*)\""       // groups 1,2
            + "|" + key + "\\s+\"([^\"]*)\""             // groups 3,4
            + "|" + key + "\\s*=\\s*'([^']*)'"           // groups 5,6
            + "|" + key + "\\s*=\\s*(\\S+)"              // groups 7,8
        guard let regex = try? NSRegularExpression(pattern: quoted) else { return args }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for m in matches where m.numberOfRanges >= 9 {
            if let key = substring(in: m, at: 1, of: scanner),
               let value = substring(in: m, at: 2, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 3, of: scanner),
                      let value = substring(in: m, at: 4, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 5, of: scanner),
                      let value = substring(in: m, at: 6, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 7, of: scanner),
                      let value = substring(in: m, at: 8, of: scanner) {
                args[key] = value
            }
        }
        return args
    }

    /// Safe group extraction: returns nil for NSNotFound so the alternation
    /// branches of an NSRegularExpression never crash `substring(with:)`.
    private static func substring(in match: NSTextCheckingResult, at index: Int,
                                  of scanner: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return scanner.substring(with: range)
    }

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

    private static func parseSingleCall(_ jsonString: String) -> WebToolCall? {
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

    private static func decodeSingleCall(_ jsonString: String) -> WebToolCall? {
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
    private static func repairedJSONObject(_ text: String) -> String? {
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

    /// Error feedback for a ```tool block whose JSON never parsed — live
    /// 2026-10-25: the host silently dropped a malformed call, the loop treated
    /// the response as a final answer and the model apologized instead of
    /// fixing its output. The returned text goes back to the model so it can
    /// re-emit a complete block; nil when every fenced block parsed.
    static func malformedToolBlockFeedback(from responseText: String) -> String? {
        let scanner = responseText as NSString
        let pattern = "```tool\\s*\\n(.*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let matches = regex.matches(in: responseText, range: NSRange(location: 0, length: scanner.length))
        for match in matches where match.numberOfRanges >= 2 {
            let block = scanner.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "\u{00A0}", with: " ")
            if parseSingleCall(block) != nil { continue }
            return """
            Your previous tool call was NOT executed: \(describeJSONProblem(block)). Re-emit the COMPLETE ```tool block with valid JSON (close every string and brace), then stop and wait for its result.
            """
        }
        return nil
    }

    private static func describeJSONProblem(_ block: String) -> String {
        var inString = false
        var escaped = false
        var stack: [Character] = []
        for ch in block {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": stack.append("}")
                case "[": stack.append("]")
                case "}", "]": if !stack.isEmpty { stack.removeLast() }
                default: break
                }
            }
        }
        if inString || escaped {
            return "its JSON string was not terminated (a quote was opened but never closed)"
        }
        if !stack.isEmpty {
            let plural = stack.count == 1 ? "" : "s"
            return "its JSON was unfinished (\(stack.count) closing bracket\(plural) missing)"
        }
        return "its JSON was invalid"
    }

    /// Stringify one JSON scalar arg. Live 2026-09-12: a naive "\(v)" turned
    /// every non-string into garbage — first the literal text "\(v)"
    /// (escaped backslash, offset ignored 3×), then — after unescaping —
    /// JSON `true` into "1" (NSNumber description), silently disabling
    /// staged/addAll/create. JSON booleans canonicalize to "true"/"false";
    /// numbers stringify. NOTE: this comment renders "\(v)" with a single
    /// backslash; the historical bug had two.
    private static func jsonScalarString(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let num = v as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() {
            return num.boolValue ? "true" : "false"
        }
        return "\(v)"
    }

    /// Tolerant boolean flag for tool args from any syntax (JSON true,
    /// short-XML staged=true, informal staged=1): "true"/"1"/"yes".
    static func isTruthyFlag(_ value: String?) -> Bool {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return v == "true" || v == "1" || v == "yes"
    }

    /// Complete-but-unfenced JSON tool calls (audit 2026-09-08, Qwen live):
    /// the model writes `{"name": "list_dir", "args": {"path": "."}}` plainly
    /// in the answer (sometimes with NBSP instead of spaces, sometimes with a
    /// stray `tool\n1\n` prefix) and no ```tool fence survives the stream.
    /// Balanced-brace scan finds each object; parseSingleCall validates it.
    private static func parseUnfencedJSONToolCalls(from text: String) -> [WebToolCall] {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let start = normalized.range(of: "{\"name\"") else { return [] }
        var calls: [WebToolCall] = []
        var searchStart = start.lowerBound
        while let openRange = normalized.range(of: "{", range: searchStart..<normalized.endIndex) {
            guard let (object, next) = balancedJSONObject(in: normalized, from: openRange.lowerBound) else { break }
            if let call = parseSingleCall(object) {
                calls.append(call)
            }
            searchStart = next
        }
        return calls
    }

    /// Extract the first balanced `{ … }` object starting at `start`, returning
    /// its text and the index right after it. Returns nil when unbalanced.
    private static func balancedJSONObject(in text: String, from start: String.Index) -> (String, String.Index)? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if escaped { escaped = false }
            else if ch == "\\" && inString { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return (String(text[start...index]), text.index(after: index))
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// True when a response contains no tool call → the model produced a final answer.
    /// Audit 2026-09-09 (Qwen live): a vendor ERROR placeholder ("The current
    /// content is empty, please regenerate.") contains no tool call either,
    /// but it is a failed generation, never a final answer.
    static func isFinalResponse(_ responseText: String) -> Bool {
        guard !WebVendorErrorPlaceholderLogic.isErrorPlaceholder(responseText) else { return false }
        return parseToolCalls(from: responseText).isEmpty
    }

    /// Format a tool result to send back to the web chat as the next message
    /// (plan Блок 2 п.14).
    static func formatToolResult(name: String, result: String) -> String {
        """
        ```tool_result
        {"name": "\(name)", "result": \(jsonEncoded(result))}
        ```
        """
    }

    private static func jsonEncoded(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        // Extract the inner string with quotes from ["..."] → "..."
        if let str = String(data: data, encoding: .utf8) {
            let trimmed = str.dropFirst().dropLast()   // remove [ ]
            return String(trimmed)
        }
        return "\"\(s)\""
    }

    /// Whether the agentic loop should stop (plan Блок 2 п.17): either the model
    /// gave a final answer or the iteration limit is reached.
    static func shouldStopLoop(iteration: Int, maxIterations: Int, lastResponse: String) -> Bool {
        iteration >= maxIterations || isFinalResponse(lastResponse)
    }

    /// Validate a tool call's arguments before executing (plan Блок 2 п.18):
    /// paths must stay within the project root UNLESS accessLevel allows broader access;
    /// destructive tools flagged. Returns `nil` when valid, or the specific validation error.
    ///
    /// `grantedRoots` are folders the user explicitly allowed access to after
    /// an out-of-project request — a path inside one of them is valid.
    static func validate(_ call: WebToolCall,
                         projectRoot: String,
                         accessLevel: AccessLevel = .askBeforeChanges,
                         grantedRoots: [String] = []) -> WebToolValidationError? {
        let call = canonicalized(call)
        guard WebEmulatedTool(rawValue: call.name) != nil else {
            return .unknownTool(call.name)
        }
        // Path boundary check is now permission-based, not hard restriction.
        // At .fullAccess, any path is allowed. At lower levels, restrict to project root.
        if accessLevel != .fullAccess,
           let path = call.arguments["path"],
           !OutOfProjectAccessLogic.isAccessible(
               path: path,
               projectRoot: projectRoot,
               grantedRoots: grantedRoots
           ) {
            return .pathEscapesProject(path)
        }
        return nil
    }

    static func requiresApproval(_ call: WebToolCall) -> Bool {
        switch WebEmulatedTool(rawValue: canonicalized(call).name) {
        case .writeFile, .editFile, .todoWrite, .taskCreate, .taskUpdate,
             .gitBranch, .gitCheckout, .gitCommit, .gitPush, .gitPull,
             .runCommand, .task:
            return true
        default:
            return false
        }
    }

    static func isPathInsideRoot(_ path: String, root: String) -> Bool {
        let normalizedRoot = resolvedPath(root)
        let candidate: String
        if path.hasPrefix("/") {
            candidate = resolvedPath(path)
        } else {
            candidate = resolvedPath(URL(fileURLWithPath: root).appendingPathComponent(path).path)
        }
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }

    /// Resolve symlinks so a symlink placed inside the project root cannot
    /// escape the root check and point at, e.g., /etc/passwd (audit ARCH-06).
    /// Strategy: (1) `realpath` for existing paths; (2) lexical `..`/`.`
    /// resolution + `realpath` for write-targets whose only missing component
    /// is the file itself; (3) as a last resort resolve the longest EXISTING
    /// ancestor via realpath and append the missing tail. `..` must be
    /// resolved lexically first — `URL.deletingLastPathComponent()` is a
    /// no-op on a trailing `..`, which made an earlier walk-up spin forever.
    private static func resolvedPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if path.withCString({ realpath($0, &buffer) }) != nil {
            return String(cString: buffer)
        }
        let lexical = lexicallyResolved(path)
        if lexical.withCString({ realpath($0, &buffer) }) != nil {
            return String(cString: buffer)
        }
        // Split into the longest existing ancestor + missing tail.
        var components = Array(
            URL(fileURLWithPath: lexical).pathComponents.filter { $0 != "/" && !$0.isEmpty }
        )
        var missingTail: [String] = []
        var resolvedAncestor: String?
        while !components.isEmpty {
            let ancestor = "/" + components.joined(separator: "/")
            if ancestor.withCString({ realpath($0, &buffer) }) != nil {
                resolvedAncestor = String(cString: buffer)
                break
            }
            missingTail.insert(components.removeLast(), at: 0)
        }
        if let resolvedAncestor {
            let trimmed = resolvedAncestor == "/" ? "" : resolvedAncestor
            return missingTail.isEmpty ? resolvedAncestor : trimmed + "/" + missingTail.joined(separator: "/")
        }
        return lexical
    }

    /// Textual resolution of `.`/`..` without touching the filesystem.
    private static func lexicallyResolved(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        var stack: [String] = []
        for component in components {
            switch component {
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            case ".", "", "/":
                continue
            default:
                stack.append(component)
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }
}

enum WebToolValidationError: Error, Equatable {
    case pathEscapesProject(String)
    case unknownTool(String)
    case incompleteJSON
}
