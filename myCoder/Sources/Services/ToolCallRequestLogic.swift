import Foundation

/// Чистая логика ленивой загрузки результатов тулов. Отвечает за три
/// вопроса: какие шаги нужно догрузить, как подмешать загруженные
/// результаты в список шагов и в каком состоянии находится каждый шаг
/// (загружен / ожидает загрузки / недоступен). Не зависит от БД и UI —
/// переносима и тестируема отдельно.
enum ToolCallRequestLogic {
    /// Ключ хранилища для шага: callID, если он есть, иначе id шага.
    /// Именно по этому ключу результат лежит в `ToolResultStore` и БД.
    ///
    /// Вход: `step`.
    /// Выход: строка-ключ.
    /// Зависимости: нет (чистая функция).
    static func storageKey(for step: ToolCallInspectorStep) -> String {
        if let callID = step.callID, !callID.isEmpty { return callID }
        return step.id
    }

    /// CallID/ключи шагов, у которых результат существует в хранилище, но
    /// ещё не загружен в память, — ровно их нужно запросить одной пачкой.
    ///
    /// Вход: `steps` — шаги вызовов инструментов.
    /// Выход: массив ключей в порядке появления шагов.
    /// Зависимости: нет (чистая функция).
    static func keysToLoad(_ steps: [ToolCallInspectorStep]) -> [String] {
        steps.filter { $0.result == nil && $0.hasStoredResult }.map(storageKey)
    }

    /// Подмешать загруженные результаты в список шагов. Шаги, у которых
    /// результат уже в памяти, не перетираются; отсутствующие в
    /// `results` ключи пропускаются (шаг остаётся как был).
    ///
    /// Вход: `results` — словарь «ключ хранилища → текст результата»;
    /// `steps` — исходные шаги.
    /// Выход: новые шаги с заполненными `result`.
    /// Зависимости: нет (чистая функция).
    static func merge(
        results: [String: String],
        into steps: [ToolCallInspectorStep]
    ) -> [ToolCallInspectorStep] {
        steps.map { step in
            guard step.result == nil, let value = results[storageKey(for: step)] else { return step }
            return ToolCallInspectorStep(
                id: step.id,
                name: step.name,
                args: step.args,
                result: value,
                callID: step.callID,
                hasStoredResult: step.hasStoredResult
            )
        }
    }

    /// Итоговый текст результата шага для отображения: сначала уже
    /// загруженный `result`, затем подгруженный из `results`.
    ///
    /// Вход: `step` — шаг; `results` — подгруженные результаты.
    /// Выход: текст результата или nil, если нигде нет.
    /// Зависимости: нет (чистая функция).
    static func displayResult(
        for step: ToolCallInspectorStep,
        results: [String: String]
    ) -> String? {
        step.result ?? results[storageKey(for: step)]
    }

    /// Шаг ожидает загрузки: результат существует в хранилище
    /// (`hasStoredResult`), но ни в `result`, ни в `results` его ещё нет.
    ///
    /// Вход: `step`, `results`.
    /// Выход: true — нужно показать состояние загрузки.
    /// Зависимости: нет (чистая функция).
    static func isPending(
        _ step: ToolCallInspectorStep,
        results: [String: String]
    ) -> Bool {
        step.result == nil && results[storageKey(for: step)] == nil && step.hasStoredResult
    }

    /// Результат недоступен: его нет ни в памяти, ни в хранилище.
    ///
    /// Вход: `step`, `results`.
    /// Выход: true — показываем честное «результат недоступен».
    /// Зависимости: нет (чистая функция).
    static func isUnavailable(
        _ step: ToolCallInspectorStep,
        results: [String: String]
    ) -> Bool {
        step.result == nil && results[storageKey(for: step)] == nil && !step.hasStoredResult
    }
}
