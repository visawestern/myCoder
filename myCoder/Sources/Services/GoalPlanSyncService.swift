import Foundation

/// Записывает todo-чеклист в план видимой цели (ЦЕЛЬ).
///
/// Вызывается сразу после исполнения todo-инструмента: чеклист — единый
/// источник правды, а `goal.plan` должен пережить перезапуск приложения.
/// Цель выбирается по контексту чата/проекта теми же правилами, что и
/// панель: активная, иначе самая новая незавершённая.
enum GoalPlanSyncService {

    /// Синхронизирует план цели с todo-элементами.
    ///
    /// Вход: `todoItems` — сохранённый чеклист; `context` — чат/проект;
    /// `homeDirectory` — где лежит `goals.json`; `fileManager` — для тестов.
    /// Выход: true, если план цели реально изменился.
    /// Зависимости: `GoalStore`, `GoalContextLogic`, `GoalPlanSyncLogic`,
    /// уведомление `myCoderGoalStoreChanged` для панели.
    @discardableResult
    static func sync(todoItems: [[String: Any]],
                     context: GoalContext,
                     homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                     fileManager: FileManager = .default) -> Bool {
        let plan = GoalPlanSyncLogic.planItems(fromTodoItems: todoItems)
        return apply(plan, context: context, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// Синхронизирует план цели с уже собранными шагами панели.
    ///
    /// Вход: `steps` — шаги правой панели; `context`, `homeDirectory`,
    /// `fileManager` — как у `sync(todoItems:…)`.
    /// Выход: true, если план цели реально изменился.
    /// Зависимости: `GoalStore`, `GoalContextLogic`, `GoalPlanSyncLogic`.
    @discardableResult
    static func sync(steps: [TaskStep],
                     context: GoalContext,
                     homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                     fileManager: FileManager = .default) -> Bool {
        let plan = GoalPlanSyncLogic.planItems(fromSteps: steps)
        return apply(plan, context: context, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// Записывает готовый план в видимую цель, если он отличается.
    ///
    /// Вход: `plan` — шаги плана; `context` — область видимости цели.
    /// Выход: true только при реальном изменении (пустой план и отсутствие
    /// цели ничего не меняют).
    /// Зависимости: `GoalStore.load/updatePlan`, `GoalContextLogic`.
    private static func apply(_ plan: [UserGoal.PlanItem],
                              context: GoalContext,
                              homeDirectory: URL,
                              fileManager: FileManager) -> Bool {
        guard !plan.isEmpty else { return false }
        let goals = GoalStore.load(homeDirectory: homeDirectory, fileManager: fileManager)
        let visible = GoalContextLogic.visibleGoals(goals, context: context)
        guard let goal = visible.first(where: { $0.state == .active })
            ?? visible.first(where: { $0.state != .done }) else { return false }
        guard plan != goal.plan else { return false }
        guard (try? GoalStore.updatePlan(
            id: goal.id,
            plan: plan,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )) == true else { return false }
        NotificationCenter.default.post(name: .init("myCoderGoalStoreChanged"), object: nil)
        return true
    }

    /// План из `todos.json` для цели без шагов.
    ///
    /// Вход: `goal` — цель; `homeDirectory` — домашняя папка.
    /// Выход: шаги плана; пусто, если файла нет/он повреждён или у цели уже
    /// есть план.
    /// Зависимости: `MyCoderPaths.todosURL`, `GoalPlanSyncLogic`.
    ///
    /// Нужен для целей, созданных ДО синхронизации: чеклист уже лежит в
    /// `todos.json`, но `goal.plan` пуст (жалоба владельца 2026-11-13).
    static func recoveredPlan(for goal: UserGoal,
                              homeDirectory: URL,
                              fileManager: FileManager = .default) -> [UserGoal.PlanItem] {
        guard goal.plan.isEmpty else { return goal.plan }
        // A projectless chat works in the home directory, so its todo file is
        // `~/.mycoder/todos.json` — the same file the executor writes.
        let root = goal.projectPath ?? homeDirectory.path
        let url = MyCoderPaths.todosURL(projectPath: root)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let items: [[String: Any]]
        if let array = json as? [[String: Any]] {
            items = array
        } else if let dict = json as? [String: Any],
                  let array = dict["todos"] as? [[String: Any]] {
            items = array
        } else {
            return []
        }
        return GoalPlanSyncLogic.planItems(fromTodoItems: items)
    }

    /// Восстанавливает пустой план цели из `todos.json` и сохраняет его.
    ///
    /// Вход: `goal` — видимая цель; `homeDirectory`.
    /// Выход: актуальный план (восстановленный или исходный).
    /// Зависимости: `recoveredPlan`, `GoalStore.updatePlan`.
    static func healPlanIfNeeded(for goal: UserGoal,
                                 homeDirectory: URL,
                                 fileManager: FileManager = .default) -> [UserGoal.PlanItem] {
        let recovered = recoveredPlan(
            for: goal,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        guard !recovered.isEmpty, recovered != goal.plan else { return recovered }
        _ = try? GoalStore.updatePlan(
            id: goal.id,
            plan: recovered,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        return recovered
    }
}
