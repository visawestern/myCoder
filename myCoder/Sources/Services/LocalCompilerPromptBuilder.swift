import Foundation

/// The prompt handed to the local model: strict rules plus the project map.
struct LocalCompilerPrompt: Equatable {
    let system: String
    let user: String
}

/// Builds the prompt for the local context compiler.
enum LocalCompilerPromptBuilder {

    static func build(userRequest: String,
                      board: ContextBoard,
                      planNode: PlanTodoItem?) -> LocalCompilerPrompt {
        var user = "Запрос пользователя:\n\(userRequest)"
        if let planNode {
            user += "\n\n[Нода текущего плана]\n"
            user += "\(planNode.id) · \(planNode.title) — статус: \(planNode.status)\n"
            if !planNode.acceptanceCriteria.isEmpty {
                user += "критерии приёмки: \(planNode.acceptanceCriteria.joined(separator: "; "))\n"
            }
            if !planNode.dependsOn.isEmpty {
                user += "зависит от: \(planNode.dependsOn.joined(separator: ", "))\n"
            }
        }
        let rendered = ContextBoardBuilder.render(board)
        user += "\n\n[Карта проекта — файлы, импорты и объявленные символы]\n"
        if rendered.isEmpty {
            user += "(проект пуст или индекс недоступен)\n"
        } else {
            user += rendered + "\n"
        }
        return LocalCompilerPrompt(system: systemRules, user: user)
    }

    static let systemRules = """
    Ты — сборщик атомарной задачи для удалённой модели-исполнителя.
    Ты НЕ пишешь код и НЕ придумываешь пути. Твоя работа:
    1) сформулировать атомарную задачу (что именно нужно сделать);
    2) назвать существующие функции, типы и переменные из карты проекта;
    3) перечислить критерии приёмки и обязательный TDD-порядок.

    Ответь ТОЛЬКО одним JSON-объектом без пояснений:
    {
      "atomicTask": "одно-два предложения: что именно сделать",
      "tdd": {
        "required": true,
        "steps": [
          "1) написать падающий тест (имя теста)",
          "2) прогнать тест — он обязан упасть",
          "3) реализовать минимально, чтобы тест позеленел",
          "4) прогнать тесты — все зелёные"
        ]
      },
      "acceptance": ["проверяемый критерий приёмки"],
      "refs": [
        {"path": "путь/из/карты.swift", "symbol": "имя()", "startLine": 10, "endLine": 40, "why": "зачем нужен"}
      ],
      "knownGaps": ["чего не нашёл в проекте"]
    }

    Правила:
    - path берётся ТОЛЬКО из карты проекта; выдуманные пути запрещены;
    - если нужного кода в проекте нет — refs оставь пустым, а отсутствие опиши в knownGaps;
    - код не пиши: только имена функций, типов и переменных;
    - atomicTask формулирует ЗАДАЧУ, а не решение.
    """
}
