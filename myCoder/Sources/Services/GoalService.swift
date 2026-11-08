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
                      language: AppLanguage) throws -> (goals: [UserGoal], reply: String) {
        switch command {
        case .create(let title):
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                return (GoalStore.load(homeDirectory: homeDirectory), "Пустая цель.")
            }
            let goal = UserGoal(title: title, state: .pending)
            try GoalStore.upsert(goal, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель создана: \(title)")

        case .start:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = goals.last else {
                return (goals, "Нет цели. Сначала задай её: /goal <текст>")
            }
            try GoalStore.setState(id: goal.id, state: .active, homeDirectory: homeDirectory)
            notifyChanged()
            let planReady = GoalPlanStatusLogic.ready(goal.plan)
            let reply = planReady
                ? "Цель запущена. Проверяю готовность плана."
                : GoalVerificationPromptBuilder.readinessMessage(language: language)
            return (GoalStore.load(homeDirectory: homeDirectory), reply)

        case .pause:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = goals.last,
                  (try? GoalStore.setState(id: goal.id, state: .paused, homeDirectory: homeDirectory)) == true else {
                return (goals, "Нет активной цели.")
            }
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель поставлена на паузу.")

        case .resume:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = goals.last,
                  (try? GoalStore.setState(id: goal.id, state: .active, homeDirectory: homeDirectory)) == true else {
                return (goals, "Нет цели для возобновления.")
            }
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель возобновлена.")

        case .delete(let index):
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard !goals.isEmpty else {
                return (goals, "Нет целей для удаления.")
            }
            let target = goals[min(index ?? 0, goals.count - 1)]
            _ = try GoalStore.remove(id: target.id, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель удалена: \(target.title)")

        case .edit(let title):
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            guard let goal = goals.last else {
                return (goals, "Нет цели для редактирования.")
            }
            guard let normalized = GoalEditingLogic.normalizedTitle(title) else {
                return (goals, "Пустое название цели.")
            }
            try GoalStore.updateTitle(id: goal.id, title: normalized, homeDirectory: homeDirectory)
            notifyChanged()
            return (GoalStore.load(homeDirectory: homeDirectory), "Цель обновлена: \(normalized)")

        case .list:
            let goals = GoalStore.load(homeDirectory: homeDirectory)
            if goals.isEmpty {
                return (goals, "Целей пока нет.")
            }
            let lines = goals.enumerated().map { i, g in
                let plural = g.plan.count == 1 ? "" : "ов"
                return "\(i). [\(g.state.rawValue)] \(g.title) (\(g.plan.count) шаг\(plural))"
            }
            return (goals, lines.joined(separator: "\n"))

        case .none:
            return (GoalStore.load(homeDirectory: homeDirectory), "")
        }
    }

    /// Tell the live UI (right-panel goals section, composer goal spoiler) that
    /// the goal store changed so it refreshes — whether the change came from the
    /// `/goal` command, the sidebar buttons, or the HTTP API.
    private static func notifyChanged() {
        NotificationCenter.default.post(name: Notification.Name("myCoderGoalStoreChanged"), object: nil)
    }
}
