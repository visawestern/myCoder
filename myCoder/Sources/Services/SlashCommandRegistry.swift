import Foundation

/// Unified slash-command model (plan Раздел 5 Блок 1). A built-in command has
/// real behavior via `kind`; a custom command is a `.md` template loaded from
/// `~/.mycoder/commands` (our own path, independent project).
struct SlashCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case builtIn(BuiltInSlashCommand)
        case custom(path: String)
    }

    let id: String
    let name: String        // without leading slash, e.g. "goal"
    let description: String
    let kind: Kind
    let icon: String

    var displayName: String { "/\(name)" }
    var isBuiltIn: Bool { if case .builtIn = kind { return true }; return false }
}

/// Built-in commands modeled on Cursor/Claude Code/Codex (plan Раздел 5 Блок 2).
enum BuiltInSlashCommand: String, CaseIterable, Identifiable {
    case goal, plan, review, test, commit, pr, explain, fix, refactor
    case document, todo, summarize, compact, context, debug, verify, remember

    var id: String { rawValue }

    var name: String { rawValue }

    var description: String {
        switch self {
        case .goal: return "Set or show the current session goal (shown in the top bar)."
        case .plan: return "Switch the session into planning mode (no mutations)."
        case .review: return "Request a review of the last diff/change in the current git repo."
        case .test: return "Run the project's tests and show the result."
        case .commit: return "Open the commit composer pre-filled from the current diff."
        case .pr: return "Create a pull request for the current branch."
        case .explain: return "Explain the selected code/file line by line."
        case .fix: return "Find and fix the described bug, using recent error context."
        case .refactor: return "Refactor the selected code without changing behavior."
        case .document: return "Add documentation/comments for this module."
        case .todo: return "Show the list of TODO/FIXME items in the project."
        case .summarize: return "Summarize this session/dialog."
        case .compact: return "Summarize the conversation and shrink the model context (keeps facts, files, open tasks)."
        case .context: return "Show the current context (open files, git branch, model/provider)."
        case .debug: return "Run a systematic debugging workflow (suggests the skill if installed)."
        case .verify: return "Verify the last change for real (run/test) before declaring done."
        case .remember: return "Save a durable fact about the project (decision, preference, task) and reuse it on later turns."
        }
    }

    var icon: String {
        switch self {
        case .goal: return "target"
        case .plan: return "list.bullet.rectangle"
        case .review: return "eye"
        case .test: return "checkmark.seal"
        case .commit: return "arrow.branch"
        case .pr: return "arrow.triangle.pull"
        case .explain: return "text.magnifyingglass"
        case .fix: return "wrench.and.screwdriver"
        case .refactor: return "square.stack.3d.up"
        case .document: return "doc.text"
        case .todo: return "checklist"
        case .summarize: return "doc.text.magnifyingglass"
        case .compact: return "rectangle.compress.vertical"
        case .context: return "info.circle"
        case .debug: return "ant"
        case .verify: return "checkmark.shield"
        case .remember: return "brain"
        }
    }

    /// Whether the command needs a git repository in the current workspace.
    var requiresGit: Bool {
        switch self {
        case .review, .commit, .pr: return true
        default: return false
        }
    }
}

/// Registry that resolves built-in + custom commands, with built-in priority
/// on name conflicts and history tracking (plan Раздел 5 Блок 1 п.5, Блок 3 п.33).
enum SlashCommandRegistry {
    static var builtInCommands: [SlashCommand] {
        BuiltInSlashCommand.allCases.map { c in
            SlashCommand(id: "builtin.\(c.rawValue)", name: c.name,
                         description: c.description, kind: .builtIn(c), icon: c.icon)
        }
    }

    /// Merge built-in commands with custom `.md` commands from the loader.
    /// Built-ins win on name conflict (custom with the same name is dropped).
    /// Disabled custom commands are excluded (SET-07).
    static func allCommands(custom: [CommandEntry] = AgentResourcesLoader.loadCommands()) -> [SlashCommand] {
        let builtIns = builtInCommands
        let builtInNames = Set(builtIns.map { $0.name })
        let customs: [SlashCommand] = custom.compactMap { entry in
            guard !builtInNames.contains(entry.name) else { return nil }
            guard entry.isEnabled else { return nil }
            return SlashCommand(id: "custom.\(entry.id)",
                                name: entry.name,
                                description: entry.description.isEmpty ? "Custom command" : entry.description,
                                kind: .custom(path: entry.path),
                                icon: "terminal")
        }
        return builtIns + customs
    }

    /// Parse a raw input line into a command + argument, if it starts with `/`.
    struct ParsedCommand: Equatable {
        let name: String
        let argument: String
    }

    static func parse(_ text: String) -> ParsedCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let afterSlash = String(trimmed.dropFirst())
        guard let firstSpace = afterSlash.firstIndex(of: " ") else {
            guard !afterSlash.isEmpty else { return nil }
            return ParsedCommand(name: afterSlash, argument: "")
        }
        let name = String(afterSlash[..<firstSpace])
        let argument = String(afterSlash[afterSlash.index(after: firstSpace)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ParsedCommand(name: name, argument: argument)
    }

    /// Resolve a parsed command against the registry.
    static func resolve(_ parsed: ParsedCommand, in commands: [SlashCommand]) -> SlashCommand? {
        commands.first { $0.name == parsed.name }
    }

    // MARK: - Usage history (in-memory, per-session; plan Блок 3 п.33)

    private static var history: [String] = []
    private static let historyLimit = 10
    /// The registry is process-wide, and slash commands can be executed from
    /// more than one task (and tests exercise it concurrently). Without this
    /// lock simultaneous `removeAll` + `insert` corrupt the array's storage.
    private static let historyLock = NSLock()

    static func recordUsage(name: String) {
        historyLock.lock()
        defer { historyLock.unlock() }
        history.removeAll { $0 == name }
        history.insert(name, at: 0)
        if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
    }

    static func usageHistory() -> [String] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return history
    }

    /// Order commands so recently-used ones come first (frecency-lite: by recency).
    static func orderedByUsage(_ commands: [SlashCommand]) -> [SlashCommand] {
        historyLock.lock()
        let snapshot = history
        historyLock.unlock()
        let used = snapshot.compactMap { name in commands.first { $0.name == name } }
        let rest = commands.filter { c in !snapshot.contains(c.name) }
        return used + rest
    }

    static func resetHistory() {
        historyLock.lock()
        defer { historyLock.unlock() }
        history.removeAll()
    }
}
