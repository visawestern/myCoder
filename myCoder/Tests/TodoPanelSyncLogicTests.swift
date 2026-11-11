import Testing
import Foundation
@testable import myCoder

/// U5 (жалоба владельца 2026-11-09): «после „план добавлен“ справа план не
/// появляется/не обновляется».
///
/// Причина: SSE-путь обновлял `AppState.currentSteps`, а локальный агентский
/// цикл (`ProjectWebToolExecutor`) исполнял `todo_write`/`task_*` и писал
/// `todos.json`, но панель об этом не узнавала. Логика ниже решает, какие
/// инструменты меняют чеклист, и преобразует сохранённые элементы в шаги
/// панели — единый источник правды для всех путей исполнения.
@MainActor
@Suite("Синхронизация todo-панели (U5)")
struct TodoPanelSyncLogicTests {

    @Test("Инструменты, меняющие чеклист, распознаются")
    func mutatingToolsRecognized() {
        for name in [
            "todo_write", "todowrite", "TodoWrite",
            "task_create", "taskcreate",
            "task_update", "task-update",
        ] {
            #expect(
                TodoPanelSyncLogic.updatesChecklist(toolName: name),
                "\(name) должен обновлять панель"
            )
        }
    }

    @Test("Читающие инструменты панель не трогают")
    func readOnlyToolsIgnored() {
        for name in ["todo_read", "todoread", "task_list", "tasklist", "read_file", "task"] {
            #expect(
                !TodoPanelSyncLogic.updatesChecklist(toolName: name),
                "\(name) не должен обновлять панель"
            )
        }
    }

    @Test("Статусы переносятся в шаги панели")
    func statusesMapped() {
        let items: [[String: Any]] = [
            ["id": "1", "content": "Сделать X", "status": "pending"],
            ["id": "2", "content": "Делается", "status": "in_progress"],
            ["id": "3", "content": "Готово", "status": "completed"],
            ["id": "4", "content": "Отменено", "status": "cancelled"],
        ]

        let steps = TodoPanelSyncLogic.steps(fromTodoItems: items)

        #expect(steps.map(\.title) == ["Сделать X", "Делается", "Готово", "Отменено"])
        #expect(steps.map(\.status) == [.waiting, .inProgress, .completed, .waiting])
    }

    @Test("Порядок элементов сохраняется")
    func orderPreserved() {
        let items: [[String: Any]] = [
            ["id": "a", "content": "Первый"],
            ["id": "b", "content": "Второй"],
            ["id": "c", "content": "Третий"],
        ]
        #expect(
            TodoPanelSyncLogic.steps(fromTodoItems: items).map(\.title)
                == ["Первый", "Второй", "Третий"]
        )
    }

    @Test("Элементы без content и пустые строки пропускаются")
    func invalidItemsSkipped() {
        let items: [[String: Any]] = [
            ["id": "1", "content": ""],
            ["id": "2"],
            ["id": "3", "content": "   "],
            ["id": "4", "content": "Живой"],
        ]
        #expect(TodoPanelSyncLogic.steps(fromTodoItems: items).map(\.title) == ["Живой"])
    }

    @Test("Пустой чеклист даёт пустую панель")
    func emptyChecklist() {
        #expect(TodoPanelSyncLogic.steps(fromTodoItems: []).isEmpty)
    }

    @Test("Неизвестный статус считается ожидающим")
    func unknownStatusIsWaiting() {
        let items: [[String: Any]] = [["id": "1", "content": "X", "status": "weird"]]
        #expect(TodoPanelSyncLogic.steps(fromTodoItems: items).map(\.status) == [.waiting])
    }
}
