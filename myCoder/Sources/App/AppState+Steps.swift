import Foundation
import SwiftUI
import AppKit

/// Шаги задачи по чатам.
extension AppState {
    /// Execution steps of the SELECTED chat.
    var currentSteps: [TaskStep] {
        get { steps(for: selectedSession?.id) }
        set { setSteps(newValue, for: selectedSession?.id) }
    }

    /// Store execution steps for one chat and persist them.
    ///
    /// Вход: `steps` — шаги плана; `sessionID` — чат, которому они
    /// принадлежат.
    /// Выход: нет.
    /// Зависимости: `ContextSessionStatusLogic.key`, `DatabaseBridge` —
    /// шаги переживают перезапуск приложения.
    func setSteps(_ steps: [TaskStep], for sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        stepsBySessionID[key] = steps
        DatabaseBridge.shared.setSessionSteps(sessionId: key, steps: steps)
    }

    /// Execution steps of one chat, whether selected or not.
    ///
    /// Вход: `sessionID` — id чата.
    /// Выход: шаги этого чата или пустой массив; при первом обращении после
    /// запуска читаются из базы программы и кешируются.
    /// Зависимости: `ContextSessionStatusLogic.key`, `DatabaseBridge`.
    func steps(for sessionID: String?) -> [TaskStep] {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return [] }
        if let cached = stepsBySessionID[key] { return cached }
        let restored = DatabaseBridge.shared.sessionSteps(forSessionID: key)
        if !restored.isEmpty {
            stepsBySessionID[key] = restored
        }
        return restored
    }
}
