import Foundation

/// Where a goal belongs: to one chat and/or to one project.
///
/// Before binding (user directive 2026-11-08) a goal was global: every chat's
/// sidebar and composer showed the same newest goal, so a goal "migrated"
/// between chats. A goal now carries `chatID`/`projectPath` and is visible
/// only in its own scope:
///
/// - chat-bound goal (`chatID != nil`) — only that chat;
/// - project goal (`chatID == nil`, `projectPath != nil`) — every chat of
///   that project;
/// - legacy goal (both nil) — only outside any chat/project, so existing
///   goals stay reachable instead of silently disappearing.
struct GoalContext: Equatable, Sendable {
    var chatID: String?
    var projectPath: String?

    init(chatID: String? = nil, projectPath: String? = nil) {
        self.chatID = chatID
        self.projectPath = projectPath
    }

    var hasChat: Bool { !(chatID ?? "").isEmpty }
    var hasProject: Bool { !(projectPath ?? "").isEmpty }
}

enum GoalContextLogic {

    /// Whether the goal belongs to this chat/project.
    static func matches(_ goal: UserGoal, context: GoalContext) -> Bool {
        let chatID = normalized(context.chatID)
        let projectPath = normalized(context.projectPath)

        if let chatID, normalized(goal.chatID) == chatID {
            return true
        }
        if let projectPath, normalized(goal.chatID) == nil, normalized(goal.projectPath) == projectPath {
            return true
        }
        // Legacy goal without any binding: visible only when the app has no
        // chat/project context, so it never floats across real chats.
        if chatID == nil && projectPath == nil {
            return normalized(goal.chatID) == nil && normalized(goal.projectPath) == nil
        }
        return false
    }

    static func visibleGoals(_ goals: [UserGoal], context: GoalContext) -> [UserGoal] {
        goals.filter { matches($0, context: context) }
    }

    /// The goal a command (/goal start/pause/…) acts on in this context.
    /// Falls back to `nil` when the context has a chat/project and no goal
    /// belongs to it — never silently picks another chat's goal.
    static func target(in goals: [UserGoal], context: GoalContext) -> UserGoal? {
        let visible = visibleGoals(goals, context: context)
        return visible.first
    }

    /// Build the goal scope from the app state values: the session's project
    /// wins over the selected workspace; a standalone chat has no project and
    /// therefore cannot inherit project goals.
    static func context(chatID: String?,
                        sessionDirectory: String?,
                        selectedWorkspacePath: String?) -> GoalContext {
        let chat = normalized(chatID)
        let directory = normalized(sessionDirectory)
        let project: String?
        if let directory, directory != ChatSession.standaloneProjectKey {
            project = directory
        } else if directory == ChatSession.standaloneProjectKey {
            project = nil
        } else {
            project = normalized(selectedWorkspacePath)
        }
        return GoalContext(chatID: chat, projectPath: project)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
