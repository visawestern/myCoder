import Foundation

/// Outcome of the access-level gate for one emulated tool call (Раздел 12 п.18).
enum WebToolPermission: Equatable {
    case allow
    case requireApproval
}

/// Maps the app's `AccessLevel` onto the emulated web-tool protocol (Раздел 12
/// п.18). Read-only tools always run; file-mutating tools require an explicit
/// approval interruption at `askBeforeChanges` and execute with undo +
/// request_history recording at higher edit levels; `run_command` — the only tool that can affect the
/// machine outside the project — is gated: it executes only at `.fullAccess`
/// and requires approval at every lower level. The old executor returned a
/// canned "requires approval" message for commands at every level without ever
/// running them; this gate decides *and* the executor enforces it.
enum WebToolAccessGate {

    static func permission(
        for call: WebToolCall,
        accessLevel: AccessLevel,
        projectRoot: String = ""
    ) -> WebToolPermission {
        // Resolve aliases FIRST: an alias like "Bash" must face the
        // run_command gate, never slip through as unknown (.none → allow).
        let call = WebToolProtocolEmulator.canonicalized(call)
        // Unknown tools fail closed below fullAccess (an unrecognized
        // capability must not execute unseen); at fullAccess they pass
        // through to the executor, which answers "error: unknown tool".
        guard let tool = WebEmulatedTool(rawValue: call.name) else {
            return accessLevel == .fullAccess ? .allow : .requireApproval
        }
        // Normalize argument spellings BEFORE inspecting them: a model may
        // send the command under "cmd"/"script" instead of "command", and an
        // empty lookup would vacantly pass isReadOnlyCommand (""/allow) —
        // letting a mutating command through without approval.
        let args = WebToolProtocolEmulator.normalizedArguments(for: tool, from: call.arguments)

        // Project boundary. Below Full access, a path outside the project
        // folder is always the user's decision — including at Edit
        // automatically, whose promise is "all edits INSIDE the project".
        // TODO/task tools carry no path and stay host-managed. `projectRoot`
        // is empty only in legacy/unit call sites, where the boundary check
        // is skipped; every production caller passes the real root.
        if accessLevel != .fullAccess,
           outOfProjectPath(for: call, projectRoot: projectRoot) != nil {
            return .requireApproval
        }

        switch tool {
        // Read-only tools — always allowed inside the project.
        case .readFile, .listDir, .grep, .gitStatus, .gitDiff, .gitLog, .glob, .todoRead,
             .webFetch, .browserFetch, .skill, .taskList, .codeSearch, .readSymbol:
            return .allow
        // File-modifying tools — ask before mutating; higher edit levels allow
        // execution after the user has chosen the corresponding global policy.
        case .writeFile, .editFile:
            return accessLevel == .askBeforeChanges ? .requireApproval : .allow
        // The whole todo/task checklist is host-managed and belongs to the
        // session, so Edit automatically may rewrite all of it.
        case .todoWrite, .taskCreate, .taskUpdate:
            return accessLevel == .askBeforeChanges ? .requireApproval : .allow
        // Git mutating operations
        case .gitBranch, .gitCheckout, .gitCommit, .gitPush, .gitPull:
            return accessLevel == .askBeforeChanges ? .requireApproval : .allow
        // Shell access — strongest capability, only at fullAccess. Read-only
        // commands (pwd, whoami, echo, ls, cat, grep, ...) are safe at any level
        // and always run; anything that can mutate the machine still requires
        // fullAccess (or an explicit approval at lower levels).
        case .runCommand:
            if isReadOnlyCommand(args["command"] ?? "") {
                return .allow
            }
            return accessLevel == .fullAccess ? .allow : .requireApproval
        // Sub-agent task tool
        case .task:
            return accessLevel == .askBeforeChanges ? .requireApproval : .allow
        }
    }

    /// Path argument that must stay inside the project for this tool, if any.
    ///
    /// TODO/task tools have no path (their store is host-managed), and git
    /// commands run inside the project root by construction, so neither is
    /// boundary-checked here.
    ///
    /// - Parameters:
    ///   - tool: canonical emulated tool.
    ///   - arguments: normalized arguments of the call.
    /// - Returns: the path to check, or nil when the tool is not path-bound.
    private static func projectPathArgument(
        for tool: WebEmulatedTool,
        arguments: [String: String]
    ) -> String? {
        switch tool {
        case .readFile, .writeFile, .editFile, .listDir, .grep, .glob, .readSymbol:
            return arguments["path"]
        default:
            return nil
        }
    }

    /// The path of `call` when it leaves the project folder, else nil.
    ///
    /// Used by the gate and by approval cards so both name the same concrete
    /// path. A call without a path (TODO/task, git, shell) is not boundary
    /// checked here: those tools either have no filesystem path or run inside
    /// the project root by construction.
    ///
    /// - Parameters:
    ///   - call: raw model call (aliases and argument spellings accepted).
    ///   - projectRoot: project folder; empty disables the check.
    /// - Returns: the offending path, or nil when the call stays inside.
    static func outOfProjectPath(for call: WebToolCall, projectRoot: String) -> String? {
        guard !projectRoot.isEmpty else { return nil }
        let call = WebToolProtocolEmulator.canonicalized(call)
        guard let tool = WebEmulatedTool(rawValue: call.name) else { return nil }
        let args = WebToolProtocolEmulator.normalizedArguments(for: tool, from: call.arguments)
        guard let path = projectPathArgument(for: tool, arguments: args),
              !WebToolProtocolEmulator.isPathInsideRoot(path, root: projectRoot) else {
            return nil
        }
        return path
    }

    /// Whether a shell command only inspects the environment and cannot mutate
    /// the machine (no file writes, package installs, git mutations, process
    /// kills, network changes, etc.). Used so read-only commands like
    /// `pwd && whoami && uname -a` run at any access level, while anything
    /// that can change state still requires fullAccess. Arguments are scanned
    /// respecting quotes; only each sub-command's first word matters.
    static func isReadOnlyCommand(_ command: String) -> Bool {
        let safe: Set<String> = [
            "pwd", "whoami", "uname", "echo", "printf", "ls", "dir", "cat",
            "head", "tail", "wc", "grep", "rg", "awk", "sort", "uniq", "cut",
            "tr", "date", "uptime", "env", "printenv", "which", "type",
            "basename", "dirname", "realpath", "true", "false", "clear",
            "hostname", "id", "groups", "who", "ps", "df", "du", "free",
            "time", "xargs", "sleep", "help", "--help", "-h",
            "sed", "nl", "less", "more", "file", "stat", "md5", "md5sum",
            "shasum", "sha256sum", "column",
        ]
        let readOnlyGit: Set<String> = [
            "status", "log", "diff", "show", "branch", "stash", "remote",
            "ls-files", "config", "rev-parse", "rev-list", "symbolic-ref", "tag",
        ]
        // Live 2026-09-12 (last chat): `sed` is in the allowlist for its
        // read-only print form but `sed` CAN mutate files (`sed -i`). Any
        // mutating flag disables the shortcut — only pure print/extraction
        // invocations run without approval.
        let mutatingSedFlags: Set<String> = ["-i", "--in-place", "-i.bak"]

        var inQuote: Character?
        var current = ""
        var words: [String] = []
        var subcommands: [[String]] = []

        func flushWord() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { words.append(trimmed) }
            current = ""
        }
        func flushSub() {
            flushWord()
            if !words.isEmpty {
                subcommands.append(words)
                words = []
            }
        }

        for ch in command {
            if let quote = inQuote {
                if ch == quote { inQuote = nil }
                current.append(ch)
            } else if ch == "\"" || ch == "'" || ch == "`" {
                inQuote = ch
            } else if ch == ">" {
                // Output redirection (>, >>, 2> …) writes to the filesystem —
                // never read-only.
                return false
            } else if ch == "&" || ch == ";" || ch == "|" || ch == "\n" {
                flushSub()
            } else if ch == " " || ch == "\t" {
                flushWord()
            } else {
                current.append(ch)
            }
        }
        flushSub()

        guard !subcommands.isEmpty else { return true }
        for sub in subcommands where !sub.isEmpty {
            let cmd = sub[0].lowercased()
            if cmd.hasPrefix("-") { continue }          // flag-only invocation (e.g. `-x e`)
            if safe.contains(cmd) {
                // sed is read-only ONLY in print form: `sed -i` rewrites the
                // file in place. Any in-place flag falls through to approval.
                if cmd == "sed", sub.dropFirst().contains(where: { mutatingSedFlags.contains($0) || $0.hasPrefix("-i") }) {
                    return false
                }
                continue
            }
            if cmd == "git", sub.count > 1, readOnlyGit.contains(sub[1].lowercased()) {
                continue
            }
            return false
        }
        return true
    }
}
