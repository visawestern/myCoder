import Foundation

/// Переводит todo-чеклист модели в план цели (ЦЕЛЬ).
///
/// Вход: элементы `todos.json` в том виде, в каком их пишут `todo_write`,
/// `task_create` и `task_update` (`content`, `status`).
/// Выход: шаги `UserGoal.PlanItem` в исходном порядке; пустые элементы
/// пропускаются.
/// Зависимости: `UserGoal.PlanItem`, `StepStatus` (только для варианта из
/// шагов панели).
///
/// Причина: `goal.plan` заполнялся только автономным раннером, а обычный
/// чат строил чеклист через todo-инструменты. Панель цели читает
/// `goal.plan`, поэтому показывала «Нет шагов» при готовом чеклисте и теряла
/// его после перезапуска (жалоба владельца 2026-11-13).
enum GoalPlanSyncLogic {

    /// План из сырых todo-элементов.
    ///
    /// Вход: `items` — словари с `content` и необязательным `status`.
    /// Выход: шаги плана; элемент без непустого `content` пропускается.
    /// Зависимости: нет (чистая функция).
    static func planItems(fromTodoItems items: [[String: Any]]) -> [UserGoal.PlanItem] {
        items.compactMap { item in
            guard let raw = item["content"] as? String else { return nil }
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return UserGoal.PlanItem(
                title: title,
                status: planStatus(fromTodoStatus: item["status"] as? String),
                note: nil
            )
        }
    }

    /// План из уже собранных шагов панели (SSE-путь `todowrite`).
    ///
    /// Вход: `steps` — шаги правой панели.
    /// Выход: шаги плана в том же порядке.
    /// Зависимости: `TaskStep`, `StepStatus`.
    static func planItems(fromSteps steps: [TaskStep]) -> [UserGoal.PlanItem] {
        steps.compactMap { step in
            let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return UserGoal.PlanItem(
                title: title,
                status: planStatus(fromStepStatus: step.status),
                note: nil
            )
        }
    }

    /// Статус todo-элемента → статус шага плана.
    ///
    /// Вход: `raw` — `pending`/`in_progress`/`completed`/`cancelled`/… или nil.
    /// Выход: `.done` для completed/done, `.inProgress` для running/
    /// in_progress, `.blocked` для cancelled/failed/blocked, иначе `.todo`.
    /// Зависимости: нет (чистая функция).
    static func planStatus(fromTodoStatus raw: String?) -> UserGoal.PlanItem.Status {
        switch (raw ?? "pending").lowercased() {
        case "completed", "complete", "done":
            return .done
        case "running", "in_progress", "in-progress", "inprogress", "active":
            return .inProgress
        case "cancelled", "canceled", "failed", "blocked", "skipped":
            return .blocked
        default:
            return .todo
        }
    }

    /// Статус шага панели → статус шага плана.
    ///
    /// Вход: `status` — `.completed`/`.inProgress`/`.waiting`.
    /// Выход: соответствующий статус плана.
    /// Зависимости: `StepStatus`.
    static func planStatus(fromStepStatus status: StepStatus) -> UserGoal.PlanItem.Status {
        switch status {
        case .completed: return .done
        case .inProgress: return .inProgress
        case .waiting: return .todo
        }
    }
}
