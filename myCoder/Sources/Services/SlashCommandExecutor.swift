import Foundation

/// The concrete action the app should perform when a slash command is entered
/// (plan Раздел 5 Блок 1/Блок 3). Pure result type so execution is testable
/// without UI: the view layer maps each case to a real side effect.
enum SlashCommandAction: Equatable {
    /// Set the session goal to `text` (persisted; shown in TopBar).
    case setSessionGoal(String)
    /// Show the current session goal (no argument given).
    case showSessionGoal
    /// Switch the session into planning mode (no mutations).
    case enterPlanMode
    /// Open the commit composer prefilled from the current diff.
    case openCommitComposer
    /// Create a pull request for the current branch.
    case createPullRequest
    /// Request a review of the last diff/change.
    case requestReview
    /// Inject a templated instruction into the outgoing message.
    case injectInstruction(String)
    /// Show contextual info (open files, branch, model/provider).
    case showContext
    /// Replace the model-bound history with a factual summary (context shrink).
    case compactConversation
    /// Store a durable project fact from `/remember <text>`.
    case remember(String)
    /// The command needs a git repo but none is present.
    case gitRequiredError(command: String)
    /// Unknown command; suggest available ones.
    case unknownCommand(name: String, available: [String])
    /// Not a command — send the text as-is.
    case passthrough(String)
}

/// Executes slash commands into `SlashCommandAction`s (plan Раздел 5 Блок 3 п.30-32).
struct SlashCommandExecutor {
    let hasGitRepo: Bool
    let commands: [SlashCommand]
    let homeDirectory: URL

    init(hasGitRepo: Bool,
         commands: [SlashCommand] = SlashCommandRegistry.builtInCommands,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.hasGitRepo = hasGitRepo
        self.commands = commands
        self.homeDirectory = homeDirectory
    }

    /// Interpret a raw input line. Returns `.passthrough` when it isn't a command.
    func execute(_ input: String) -> SlashCommandAction {
        guard let parsed = SlashCommandRegistry.parse(input) else {
            return .passthrough(input)
        }
        guard let command = SlashCommandRegistry.resolve(parsed, in: commands) else {
            return .unknownCommand(name: parsed.name,
                                   available: commands.map { $0.name }.sorted())
        }
        SlashCommandRegistry.recordUsage(name: command.name)

        guard case .builtIn(let builtIn) = command.kind else {
            // Custom .md command → inject its real template body with the
            // user's argument substituted (plan Раздел 5 Блок 3; SET-07).
            let template = CommandFileManager.templateBody(
                named: command.name,
                argument: parsed.argument,
                homeDirectory: homeDirectory
            )
            let instruction = template ?? "/\(command.name) \(parsed.argument)"
                .trimmingCharacters(in: .whitespaces)
            return .injectInstruction(instruction)
        }

        // Git-required commands fail cleanly without a repo (plan Блок 3 п.35).
        if builtIn.requiresGit && !hasGitRepo {
            return .gitRequiredError(command: builtIn.name)
        }

        switch builtIn {
        case .goal:
            return parsed.argument.isEmpty ? .showSessionGoal : .setSessionGoal(parsed.argument)
        case .plan:
            return .enterPlanMode
        case .commit:
            return .openCommitComposer
        case .pr:
            return .createPullRequest
        case .review:
            return .requestReview
        case .context:
            return .showContext
        case .remember:
            return .remember(parsed.argument)
        case .test:
            return .injectInstruction("Run the project's tests and show the result. \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .explain:
            return .injectInstruction("Explain the following code/file line by line: \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .fix:
            return .injectInstruction("Find and fix the described bug: \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .refactor:
            return .injectInstruction("Refactor the following without changing behavior: \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .document:
            return .injectInstruction("Add documentation/comments for: \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .todo:
            return .injectInstruction("List the TODO/FIXME items in the project.")
        case .summarize:
            return .injectInstruction("Summarize this session/dialog.")
        case .compact:
            return .compactConversation
        case .debug:
            return .injectInstruction("Run a systematic debugging workflow for: \(parsed.argument)".trimmingCharacters(in: .whitespaces))
        case .verify:
            return .injectInstruction("Verify the last change for real (run/test) before declaring done.")
        }
    }
}

/// Session goal state, persisted per session (plan Раздел 5 Блок 1 п.7-8).
/// The DB column `session_goal` is written by the app layer; this store is the
/// in-memory + serialization contract that keeps it testable.
struct SessionGoal: Codable, Equatable {
    var text: String
    var setAt: Date

    init(text: String, setAt: Date = Date()) {
        self.text = text
        self.setAt = setAt
    }
}

enum SessionGoalLogic {
    /// Apply a `setSessionGoal` action, returning the new goal (or nil to clear).
    static func apply(action: SlashCommandAction, current: SessionGoal?) -> SessionGoal? {
        switch action {
        case .setSessionGoal(let text):
            return text.isEmpty ? nil : SessionGoal(text: text)
        default:
            return current
        }
    }

    /// TopBar badge label for a goal (truncated) (plan Блок 1 п.9).
    static func badgeLabel(for goal: SessionGoal?, maxLength: Int = 40) -> String? {
        guard let goal = goal, !goal.text.isEmpty else { return nil }
        if goal.text.count <= maxLength { return "🎯 \(goal.text)" }
        let idx = goal.text.index(goal.text.startIndex, offsetBy: maxLength)
        return "🎯 \(goal.text[..<idx])…"
    }
}
