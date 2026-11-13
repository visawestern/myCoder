import Foundation

/// Deterministic stage-1 validation of a tool call against the concrete tool
/// schema (directive 2026-11-13, план п.8).
///
/// Purpose: before ANY tool executes, its arguments are checked against the
/// tool's own required-argument list and closed value domains. This runs
/// locally, with no model in the loop, so a call that cannot possibly work is
/// rejected with the exact missing key instead of surfacing as a vague
/// executor error ("error: missing path/content") or, worse, executing with
/// empty arguments.
///
/// Only syntax is checked here — never intent, safety or paths (paths stay in
/// `WebToolProtocolEmulator.validate`). Tools whose arguments are all optional
/// (`list_dir`, `git_status`, `git_diff`, `git_log`, `git_branch`, `git_push`,
/// `git_pull`, `glob`, `todo_read`, `task_list`, `skill`) must never demand an
/// argument, so a legitimate call with `{}` is not blocked.
///
/// Input: canonical tool + arguments already normalized to canonical keys
/// (`file_path` → `path`, `cmd` → `command`).
/// Output: nil when the call satisfies the schema, otherwise one actionable
/// sentence naming the tool and the missing/invalid key.
/// Dependencies: `WebEmulatedTool` only (pure logic, fully testable).
enum WebToolSchemaValidator {

    /// Required argument keys per tool, in the order a model should read them.
    static func requiredArguments(for tool: WebEmulatedTool) -> [String] {
        switch tool {
        case .readFile:
            return ["path"]
        case .writeFile:
            return ["path", "content"]
        case .editFile:
            return ["path", "old", "new"]
        case .grep:
            return ["pattern"]
        case .runCommand:
            return ["command"]
        case .gitCheckout:
            return ["branch"]
        case .gitCommit:
            return ["message"]
        case .codeSearch:
            return ["query"]
        case .webFetch, .browserFetch:
            return ["url"]
        case .todoWrite:
            return ["todos"]
        case .task:
            return ["description", "prompt"]
        case .taskCreate:
            return ["content"]
        case .taskUpdate:
            return ["id"]
        case .lsp:
            return ["operation"]
        // Every other tool works with an empty argument bag: listing, status
        // queries, history, branch/push/pull defaults, todo reading, task
        // listing and skill listing all have meaningful defaults.
        case .listDir, .gitStatus, .gitDiff, .gitLog, .gitBranch,
             .gitPush, .gitPull, .glob, .todoRead, .taskList, .skill:
            return []
        case .readSymbol:
            // Handled by `readSymbolViolation`: id OR path+name.
            return []
        }
    }

    /// The closed set of `lsp` operations the executor understands.
    static let lspOperations = ["diagnostics", "definition", "references", "hover", "completion"]

    /// Check one canonicalized, argument-normalized call.
    ///
    /// Input: canonical tool and its normalized arguments.
    /// Output: nil when valid; otherwise the violation sentence.
    /// Dependencies: `requiredArguments`, `lspOperations`.
    static func violation(for tool: WebEmulatedTool,
                          arguments: [String: String]) -> String? {
        for key in requiredArguments(for: tool) where isMissing(arguments[key]) {
            return "missing required argument '\(key)' for \(tool.rawValue)"
        }
        switch tool {
        case .readSymbol:
            return readSymbolViolation(arguments)
        case .lsp:
            return lspViolation(arguments)
        default:
            return nil
        }
    }

    /// `read_symbol` accepts an indexed id OR a (path, name) pair; neither
    /// alone is usable, so the message states both accepted shapes.
    static func readSymbolViolation(_ arguments: [String: String]) -> String? {
        if !isMissing(arguments["id"]) { return nil }
        if !isMissing(arguments["path"]), !isMissing(arguments["name"]) { return nil }
        return "read_symbol needs either 'id' or both 'path' and 'name'"
    }

    /// `lsp` takes one operation out of a closed set; anything else would only
    /// reach the executor and produce a dead-end error, so it is rejected here
    /// with the allowed values in the message.
    static func lspViolation(_ arguments: [String: String]) -> String? {
        guard let raw = arguments["operation"] else { return nil }   // missing → reported above
        let operation = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lspOperations.contains(operation) else {
            return "lsp operation '\(raw)' is not one of \(lspOperations.joined(separator: "|"))"
        }
        return nil
    }

    /// A key counts as missing when absent or blank: an empty string carries no
    /// usable value (`""` as a command or path must not reach the executor).
    static func isMissing(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
