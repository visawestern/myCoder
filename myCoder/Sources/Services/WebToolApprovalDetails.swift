import Foundation

/// One argument row rendered in the approval dialog.
struct WebToolApprovalParameter: Identifiable, Equatable {
    let name: String
    let value: String

    var id: String { name }
}

/// Human-readable description of a tool call that needs the user's explicit
/// consent. The local-model loop pauses BEFORE execution, shows this in an
/// inline card directly after the tool call, and only runs the tool after an
/// Allow verdict.
struct WebToolApprovalDetails: Equatable {
    let tool: String
    let action: String
    let location: String
    let projectRoot: String
    let parameters: [WebToolApprovalParameter]
    let impact: String
    let rationale: String?

    init(call: WebToolCall, projectRoot: String, modelContext: String = "") {
        let canonical = WebToolProtocolEmulator.canonicalized(call)
        let resolvedTool = WebEmulatedTool(rawValue: canonical.name)
        let arguments = resolvedTool.map {
            WebToolProtocolEmulator.normalizedArguments(for: $0, from: canonical.arguments)
        } ?? canonical.arguments

        self.tool = canonical.name
        self.projectRoot = projectRoot
        self.action = Self.action(for: resolvedTool, toolName: canonical.name)
        self.location = Self.location(for: resolvedTool, arguments: arguments, projectRoot: projectRoot)
        self.parameters = arguments.keys.sorted().map { key in
            WebToolApprovalParameter(name: key, value: Self.displayValue(key: key, raw: arguments[key] ?? ""))
        }
        self.impact = Self.impact(for: resolvedTool, arguments: arguments, projectRoot: projectRoot)
        self.rationale = Self.rationale(from: modelContext)
    }

    /// Full text used by the inline approval card and the approval mailbox.
    var formattedMessage: String {
        var lines = [
            "Tool: \(tool)",
            "Action: \(action)",
            "Location: \(location)",
            "Project: \(projectRoot)",
        ]
        if let rationale, !rationale.isEmpty {
            lines.append("Model context: \(rationale)")
        }
        if !parameters.isEmpty {
            lines.append("Parameters:")
            lines.append(contentsOf: parameters.map { "  - \($0.name) = \($0.value)" })
        }
        lines.append("Effect: \(impact)")
        lines.append("myCoder is paused until you choose Allow or Deny.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Description building

    private static func action(for tool: WebEmulatedTool?, toolName: String) -> String {
        guard let tool else { return "Run the \(toolName) tool (unrecognized by this build)." }
        switch tool {
        case .writeFile: return "Create or overwrite a file."
        case .editFile: return "Replace an exact substring in an existing file."
        case .runCommand: return "Run a shell command on this machine."
        case .gitBranch: return "List or create git branches."
        case .gitCheckout: return "Switch the project to another git branch."
        case .gitCommit: return "Create a git commit."
        case .gitPush: return "Push local commits to a remote repository."
        case .gitPull: return "Pull remote commits into the current branch."
        case .todoWrite: return "Write or update the session task checklist."
        case .taskCreate: return "Add a task to the session checklist."
        case .taskUpdate: return "Update a task in the session checklist or move a task of the execution plan."
        case .task: return "Launch a sub-agent for a complex task."
        default: return tool.description
        }
    }

    private static func location(for tool: WebEmulatedTool?,
                                 arguments: [String: String],
                                 projectRoot: String) -> String {
        if tool == .runCommand {
            return "Working directory: \(projectRoot)"
        }
        if let path = arguments["path"], !path.isEmpty {
            return path
        }
        return projectRoot
    }

    private static func impact(for tool: WebEmulatedTool?,
                               arguments: [String: String],
                               projectRoot: String) -> String {
        let path = arguments["path"] ?? projectRoot
        guard let tool else {
            return "The tool is not recognized by this build; below Full access it is gated for safety."
        }
        switch tool {
        case .writeFile:
            return "Creates or replaces \(path) with \(arguments["content"]?.count ?? 0) characters of content."
        case .editFile:
            return "Replaces \((arguments["old"] ?? "").count) characters with \((arguments["new"] ?? "").count) characters in \(path)."
        case .runCommand:
            return "Runs with your user permissions and can change files or system state outside the project."
        case .gitCommit:
            return "Creates a git commit in \(projectRoot); commits become part of the project history."
        case .gitPush:
            return "Sends local commits to the configured remote; this publishes code outside this machine."
        case .gitPull:
            return "Fetches and merges remote commits into the current branch."
        case .gitBranch, .gitCheckout:
            return "Changes git branch state in \(projectRoot)."
        case .todoWrite, .taskCreate, .taskUpdate:
            return "Changes the session task checklist only (a plan task id moves the task's status in the execution plan)."
        case .task:
            return "Starts a sub-agent that may make further tool calls against this project."
        default:
            return "Runs \(tool.rawValue) against \(projectRoot)."
        }
    }

    private static func rationale(from modelContext: String) -> String? {
        var text = modelContext
        if let regex = try? NSRegularExpression(pattern: "```tool[\\s\\S]*?```") {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return bounded(trimmed, limit: 600)
    }

    private static func displayValue(key: String, raw: String) -> String {
        if isSensitive(key: key) { return "<redacted>" }
        switch key {
        case "content", "old", "new", "prompt":
            return "\"\(escapedPreview(raw, limit: 160))\" (\(raw.count) chars)"
        case "command":
            return bounded(raw, limit: 2_000)
        default:
            return bounded(raw, limit: 500)
        }
    }

    private static func isSensitive(key: String) -> Bool {
        let lower = key.lowercased()
        return ["password", "token", "secret", "api_key", "apikey", "authorization"]
            .contains { lower.contains($0) }
    }

    private static func escapedPreview(_ raw: String, limit: Int) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return bounded(escaped, limit: limit)
    }

    private static func bounded(_ raw: String, limit: Int) -> String {
        guard raw.count > limit else { return raw }
        return String(raw.prefix(limit)) + "… (\(raw.count) chars)"
    }
}
