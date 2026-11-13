import Foundation

/// High-level goal (ЦЕЛЬ) operations used by the UI and the `/goal` command.
/// Pure enough to test with a temporary home directory.
enum GoalService {

    /// Apply a parsed `/goal` command. Returns the updated goal list and a
    /// chat reply (confirmation / errors). Does not start long verification
    /// work — that belongs to `GoalVerificationService`. The localized *core*
    /// prompts (продолжай по плану, адвокат дьявола) live in
    /// `GoalVerificationPromptBuilder`; these short confirmations are plain
    /// strings for v1.
    static func apply(_ command: GoalCommand,
                      homeDirectory: URL,
                      language: AppLanguage,
                      context: GoalContext = GoalContext()) throws -> (goals: [UserGoal], reply: String, createdGoalID: UUID?) {
        switch command {
        case .create(let title):
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                return (GoalStore.load(homeDirectory: homeDirectory), "Пустая цель.", nil)
            }
            let goal = UserGoal(
                title: title,
                state: .pending,
                projectPath: normalized(context.projectPath),
                chatID: normalized(context.chatID)
            )
            try GoalStore.upsert(goal, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель создана: \(title)", goal.id)

        case .start:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = target(in: goals, context: context) else {
                return (goals, "Нет цели. Сначала задай её: /goal <текст>", nil)
            }
            try GoalStore.setState(id: goal.id, state: .active, homeDirectory: homeDirectory)
            notifyChanged()
            let planReady = GoalPlanStatusLogic.ready(goal.plan)
            let reply = planReady
                ? "Цель запущена. Проверяю готовность плана."
                : GoalVerificationPromptBuilder.readinessMessage(language: language)
            return (GoalStore.load(homeDirectory: homeDirectory), reply, nil)

        case .pause:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = target(in: goals, context: context),
                  (try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: homeDirectory)) == true else {
                return (goals, "Нет активной цели.", nil)
            }
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель поставлена на паузу.", nil)

        case .resume:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = target(in: goals, context: context),
                  (try? GoalStore.setState(id: goal.id, state: .active, homeDirectory: homeDirectory)) == true else {
                return (goals, "Нет цели для возобновления.", nil)
            }
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель возобновлена.", nil)

        case .delete(let index):
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            let scoped = scopedGoals(goals, context: context)
            guard !scoped.isEmpty else {
                return (goals, "Нет целей для удаления.", nil)
            }
            let target = scoped[min(index ?? 0, scoped.count - 1)]
            _ = try GoalStore.remove(id: target.id, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель удалена: \(target.title)", nil)

        case .edit(let title):
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = target(in: goals, context: context) else {
                return (goals, "Нет цели для редактирования.", nil)
            }
            guard let normalized = GoalEditingLogic.normalizedTitle(title) else {
                return (goals, "Пустое название цели.", nil)
            }
            try GoalStore.updateTitle(id: goal.id, title: normalized, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель обновлена: \(normalized)", nil)

        case .list:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            let scoped = scopedGoals(goals, context: context)
            if scoped.isEmpty {
                return (goals, "Целей пока нет.", nil)
            }
            let lines = scoped.enumerated().map { i, g in
                let plural = g.plan.count == 1 ? "" : "ов"
                return "\(i). [\(g.state.rawValue)] \(g.title) (\(g.plan.count) шаг\(plural))"
            }
            return (goals, lines.joined(separator: "\n"), nil)

        case .none:
            return (GoalStore.load(homeDirectory: homeDirectory), "", nil)
        }
    }

    /// Goals visible in this context. Without any chat/project (e.g. an API
    /// caller that did not pass one) the whole list is shown, preserving the
    /// pre-binding behaviour for `/goal list`.
    private static func scopedGoals(_ goals: [UserGoal], context: GoalContext) -> [UserGoal] {
        if !context.hasChat && !context.hasProject {
            return goals
        }
        return GoalContextLogic.visibleGoals(goals, context: context)
    }

    /// The goal a state command acts on. Inside a chat/project only a goal of
    /// that scope is eligible; outside any scope the newest goal is used so
    /// `/goal` keeps working.
    private static func target(in goals: [UserGoal], context: GoalContext) -> UserGoal? {
        if let target = GoalContextLogic.target(in: goals, context: context) {
            return target
        }
        if !context.hasChat && !context.hasProject {
            return goals.first
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Tell the live UI (right-panel goals section, composer goal spoiler) that
    /// the goal store changed so it refreshes — whether the change came from the
    /// `/goal` command, the sidebar buttons, or the HTTP API.
    static func notifyChanged() {
        NotificationCenter.default.post(name: Notification.Name("myCoderGoalStoreChanged"), object: nil)
    }
}
