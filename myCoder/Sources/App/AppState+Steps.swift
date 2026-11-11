import Foundation
import SwiftUI
import AppKit

/// Шаги задачи по чатам.
extension AppState {
    /// Execution steps of the SELECTED chat.
    var currentSteps: [TaskStep] {
        get {
            ContextSessionStatusLogic.steps(
                stepsBySession: stepsBySessionID,
                selectedSessionID: selectedSession?.id
            )
        }
        set { setSteps(newValue, for: selectedSession?.id) }
    }

    /// Store execution steps for one chat.
    ///
    /// Вход: `steps` — шаги плана; `sessionID` — чат, которому они принадлежат.
    /// Выход: нет.
    /// Зависимости: `ContextSessionStatusLogic.key`.
    func setSteps(_ steps: [TaskStep], for sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        stepsBySessionID[key] = steps
    }

    /// Execution steps of one chat, whether selected or not.
    ///
    /// Вход: `sessionID` — id чата.
    /// Выход: шаги этого чата или пустой массив.
    /// Зависимости: `ContextSessionStatusLogic.steps`.
    func steps(for sessionID: String?) -> [TaskStep] {
        ContextSessionStatusLogic.steps(
            stepsBySession: stepsBySessionID,
            selectedSessionID: sessionID
        )
    }
}
