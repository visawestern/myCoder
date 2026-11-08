import Foundation

/// Parses `/goal` slash commands typed by the user. The command sets a goal,
/// then controls its lifecycle (start / pause / resume / delete).
enum GoalCommand: Equatable, Sendable {
    /// `/goal <text>` or `/goal create <text>` — create a new goal.
    case create(title: String)
    /// `/goal start` — start the goal (readiness check + auto-continue).
    case start
    /// `/goal pause` — pause (e.g. after an error that retries did not clear).
    case pause
    /// `/goal resume` — resume a paused goal.
    case resume
    /// `/goal delete [index]` — delete a goal (defaults to the latest).
    case delete(index: Int?)
    /// `/goal list` — list goals.
    case list
    /// Not a goal command.
    case none
}

enum GoalCommandLogic {

    /// A line is a goal command only when it starts with `/goal` (case-insensitive).
    static func isGoalCommand(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .hasPrefix("/goal")
    }

    static func parse(_ line: String) -> GoalCommand {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isGoalCommand(trimmed) else { return .none }
        var rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        // A subcommand is the first word (if any).
        let words = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return .list }

        switch first.lowercased() {
        case "start":
            return .start
        case "pause":
            return .pause
        case "resume":
            return .resume
        case "list":
            return .list
        case "delete":
            if words.count > 1, let index = Int(words[1]), index >= 0 {
                return .delete(index: index)
            }
            return .delete(index: nil)
        case "create":
            let title = words.dropFirst().joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if title.isEmpty { return .list }
            return .create(title: title)
        default:
            // No subcommand → the whole line is the goal title.
            return .create(title: rest)
        }
    }
}
