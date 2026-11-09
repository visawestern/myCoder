import Foundation

/// Синхронизация правой todo-панели с реальным чеклистом (U5).
///
/// Панель (`AppState.currentSteps`) обновлялась только по SSE-событиям
/// сервера. Локальный агентский цикл исполняет `todo_write` / `task_create` /
/// `task_update` через `ProjectWebToolExecutor` и пишет `todos.json`, но
/// панель об этом не узнавала — пользователь видел «план добавлен» без плана.
///
/// Здесь две чистые функции: какие инструменты меняют чеклист и как
/// преобразовать сохранённые элементы в шаги панели. Вызывающий код читает
/// `todos.json` после исполнения инструмента — единый источник правды.
enum TodoPanelSyncLogic {

    /// Меняет ли инструмент сохранённый чеклист.
    ///
    /// Вход: `toolName` — имя инструмента в любом регистре/написании
    /// (`todo_write`, `TodoWrite`, `task-create`).
    /// Выход: true для `todo_write`, `task_create`, `task_update`;
    /// false для чтения (`todo_read`, `task_list`) и остальных инструментов.
    /// Зависимости: нет (чистая функция).
    static func updatesChecklist(toolName: String) -> Bool {
        let normalized = toolName
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "todowrite", "taskcreate", "taskupdate":
            return true
        default:
            return false
        }
    }

    /// Шаги панели из сохранённых элементов `todos.json`.
    ///
    /// Вход: `items` — массив словарей с `content` и необязательным `status`.
    /// Выход: `TaskStep` в исходном порядке; элементы без непустого
    /// `content` пропускаются.
    /// Зависимости: `TaskStep`, `StepStatus`.
    static func steps(fromTodoItems items: [[String: Any]]) -> [TaskStep] {
        items.compactMap { item in
            guard let rawContent = item["content"] as? String else { return nil }
            let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return TaskStep(title: content, status: status(from: item["status"] as? String))
        }
    }

    /// Статус элемента чеклиста → статус шага панели.
    ///
    /// Вход: `raw` — статус из JSON (`pending`, `in_progress`, `completed`,
    /// `cancelled`, …) или nil.
    /// Выход: `.completed` для done/completed, `.inProgress` для
    /// running/in_progress, иначе `.waiting` (включая cancelled и неизвестные).
    /// Зависимости: `StepStatus`.
    private static func status(from raw: String?) -> StepStatus {
        switch (raw ?? "pending").lowercased() {
        case "done", "completed":
            return .completed
        case "running", "in_progress", "in-progress", "inprogress", "active":
            return .inProgress
        default:
            return .waiting
        }
    }
}
