import Foundation

/// Git-related UI action presented as a dialog. E08 (Раздел 5 п.13/15/16):
/// slash commands must open the REAL existing flows instead of sending the
/// raw command text to the model. ContentView presents one `.sheet(item:)`
/// that switches on this value.
enum GitUIAction: Int, Identifiable, Equatable {
    case openCommitComposer
    case openReviewDialog
    case openPublishWizard
    case createPullRequest

    var id: Int { rawValue }
}

/// A concrete, observable side effect of a slash command (Раздел 5 Блок 2).
/// The view layer applies each case to real app state / UI; nothing here is
/// a placeholder — every case ends in a visible user-visible result.
enum SlashEffect: Equatable {
    /// Switch the agent mode (e.g. "plan" for `/plan`).
    case setAgentMode(String)
    /// Append a local assistant message (feedback / context summary).
    case appendAssistantMessage(String)
    /// Open a git dialog via `AppState.pendingGitAction`.
    case openGitAction(GitUIAction)
    /// Replace the outgoing text with a templated instruction.
    case injectInstruction(String)
    /// Clear the input field (the command itself must not be sent).
    case clearInput
}

/// Read-only context the dispatcher needs to decide effects.
struct SlashDispatchContext: Equatable {
    var hasGitRepo: Bool
    var hasRemote: Bool
    var branch: String?
    var modelID: String
    var providerID: String
    var agentMode: String
    var workspacePath: String?
    var testRunner: String?
    var changedFileCount: Int
}

/// Maps a parsed slash-command action + app context to concrete side effects.
/// Pure and Foundation-only so the mapping is unit-testable without UI.
enum SlashCommandDispatcher {
    static func effects(for action: SlashCommandAction, context: SlashDispatchContext) -> [SlashEffect] {
        switch action {
        case .enterPlanMode: // п.12 — switch session into planning mode
            return [
                .setAgentMode("plan"),
                .appendAssistantMessage("🛠 Plan mode enabled — the next message will be sent to the plan agent without making changes."),
                .clearInput,
            ]
        case .openCommitComposer: // п.15 — open the existing commit composer
            return [
                .openGitAction(.openCommitComposer),
                .appendAssistantMessage("Opening the commit composer with the pending diff…"),
                .clearInput,
            ]
        case .createPullRequest: // п.16 — PR dialog, or publish wizard if no remote
            if context.hasRemote {
                return [
                    .openGitAction(.createPullRequest),
                    .appendAssistantMessage("Opening the pull request dialog for branch \(context.branch ?? "current")…"),
                    .clearInput,
                ]
            }
            return [
                .openGitAction(.openPublishWizard),
                .appendAssistantMessage("No git remote configured — opening the GitHub publish wizard so the branch can be pushed first."),
                .clearInput,
            ]
        case .requestReview: // п.13 — review the pending diff
            return [
                .openGitAction(.openReviewDialog),
                .appendAssistantMessage("Requesting review of the pending changes…"),
                .clearInput,
            ]
        case .showContext: // п.23 — show quick context reference in chat
            return [
                .appendAssistantMessage(contextSummary(context)),
                .clearInput,
            ]
        case .setSessionGoal, .showSessionGoal, .gitRequiredError, .unknownCommand,
             .compactConversation, .remember:
            // Handled directly by ChatPanelView (existing behavior) — nothing
            // to send to the model.
            return [.clearInput]
        case .injectInstruction(let instruction): // /test /explain /fix /refactor /document /todo /summarize /debug /verify
            return [.injectInstruction(enrichTestInstruction(instruction, runner: context.testRunner))]
        case .passthrough:
            return []
        }
    }

    /// Раздел 5 п.14/36: `/test` must name the DETECTED test runner instead of
    /// a generic instruction (and leave the text unchanged when none exists —
    /// the model then reports what it finds).
    static func enrichTestInstruction(_ instruction: String, runner: String?) -> String {
        guard instruction.hasPrefix("Run the project's tests") else { return instruction }
        let argument = instruction
            .replacingOccurrences(of: "Run the project's tests and show the result.", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let runner, !runner.isEmpty else { return instruction }
        var text = "Run the project's tests using `\(runner)` and show the result."
        if !argument.isEmpty {
            text += " \(argument)"
        }
        return text
    }

    /// Markdown summary of the current workspace context for `/context`.
    static func contextSummary(_ c: SlashDispatchContext) -> String {
        var lines = ["🧭 **Context**"]
        if let path = c.workspacePath, !path.isEmpty {
            lines.append("• Workspace: `\(path)`")
        }
        lines.append("• Agent mode: `\(c.agentMode)`")
        lines.append("• Model: `\(c.modelID.isEmpty ? "—" : c.modelID)`")
        lines.append("• Provider: `\(c.providerID.isEmpty ? "—" : c.providerID)`")
        if let branch = c.branch, !branch.isEmpty {
            lines.append("• Git branch: `\(branch)`")
        }
        if c.hasGitRepo {
            lines.append(c.hasRemote ? "• Git remote: configured" : "• Git remote: none")
            lines.append("• Changed files: \(c.changedFileCount)")
        } else {
            lines.append("• Git: no repository")
        }
        if let runner = c.testRunner, !runner.isEmpty {
            lines.append("• Test runner: `\(runner)`")
        }
        return lines.joined(separator: "\n")
    }
}

/// Detects the project's test runner from well-known files (Раздел 5 п.14/36).
/// `/test` must name the real runner instead of a generic instruction, and
/// report clearly when none is found.
enum TestRunnerDetector {
    static func detect(
        in directory: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        let candidates: [(fileName: String, runner: String)] = [
            ("Package.swift", "swift test"),
            ("package.json", "npm test"),
            ("yarn.lock", "yarn test"),
            ("pytest.ini", "pytest"),
            ("conftest.py", "pytest"),
            ("pyproject.toml", "pytest"),
            ("tox.ini", "tox"),
            ("Cargo.toml", "cargo test"),
        ]
        for candidate in candidates where fileExists((directory as NSString).appendingPathComponent(candidate.fileName)) {
            return candidate.runner
        }
        return nil
    }
}
