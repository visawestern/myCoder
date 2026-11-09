import Foundation

/// Выбор состояния, привязанного к чату (C1/C2).
///
/// Сборка контекста, её журнал и шаги плана раньше жили в глобальных полях
/// `AppState`. Из-за этого чат B показывал строку «собираем контекст» чата A,
/// не мог отправить сообщение, пока A собирает, а бейдж цели в шапке брал
/// шаги чужого чата (жалоба владельца 2026-11-09). Здесь чистые правила
/// выбора: по выбранной сессии возвращается только её собственное состояние.
enum ContextSessionStatusLogic {

    /// Ключ хранения per-session состояния.
    ///
    /// Вход: `sessionID` — id чата или nil.
    /// Выход: обрезанный id; пустая строка для nil/пустого id.
    /// Зависимости: нет (чистая функция).
    static func key(_ sessionID: String?) -> String {
        guard let sessionID else { return "" }
        return sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Идёт ли сборка контекста у выбранного чата.
    ///
    /// Вход: `compiling` — id чатов со сборкой в полёте; `selectedSessionID`.
    /// Выход: true только для непустого id, который есть в наборе.
    /// Зависимости: нет (чистая функция).
    static func isCompiling(compiling: Set<String>, selectedSessionID: String?) -> Bool {
        let selected = key(selectedSessionID)
        guard !selected.isEmpty else { return false }
        return compiling.contains(selected)
    }

    /// Текущая стадия сборки выбранного чата.
    ///
    /// Вход: `stages` — стадии по id чата; `selectedSessionID`.
    /// Выход: строка стадии или "" для чужого/неизвестного чата.
    /// Зависимости: нет (чистая функция).
    static func stage(stages: [String: String], selectedSessionID: String?) -> String {
        stages[key(selectedSessionID)] ?? ""
    }

    /// Журнал сборки выбранного чата.
    ///
    /// Вход: `logs` — журналы по id чата; `selectedSessionID`.
    /// Выход: журнал чата или `.empty` для чужого/неизвестного чата.
    /// Зависимости: `ContextAssemblyLogLogic.Log`.
    static func log(
        logs: [String: ContextAssemblyLogLogic.Log],
        selectedSessionID: String?
    ) -> ContextAssemblyLogLogic.Log {
        logs[key(selectedSessionID)] ?? .empty
    }

    /// Шаги плана выбранного чата.
    ///
    /// Вход: `stepsBySession` — шаги по id чата; `selectedSessionID`.
    /// Выход: шаги чата или пустой массив для чужого/неизвестного чата.
    /// Зависимости: `TaskStep`.
    static func steps(
        stepsBySession: [String: [TaskStep]],
        selectedSessionID: String?
    ) -> [TaskStep] {
        stepsBySession[key(selectedSessionID)] ?? []
    }
}
