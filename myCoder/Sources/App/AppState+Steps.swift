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

    /// Улучшение текущего чата до проекта (директива 2026-11-13): чат НЕ
    /// заменяется новым — та же сессия привязывается к папке проекта. Модель,
    /// сообщения, цель и шаги сохраняются; меняется только рабочая папка и
    /// статус «открыт проект».
    ///
    /// Вход: `sessionID` — чат; `path` — папка проекта.
    /// Выход: нормализованный путь проекта или nil (чат не найден/путь пуст).
    /// Зависимости: `createNewProject`, `DatabaseBridge.bindSessionToProject`,
    /// `SessionProjectBindLogic`.
    @MainActor
    @discardableResult
    func bindSessionToProject(sessionID: String?, path: String) -> String? {
        guard let sessionID,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return nil
        }
        let normalized = ChatSession.normalizedPath(path)
        // Проект регистрируется (если его ещё нет) — workspace и запись в БД.
        createNewProject(name: (normalized as NSString).lastPathComponent, path: normalized)
        // Та же сессия, новая папка.
        let bound = SessionProjectBindLogic.boundSession(sessions[index], to: normalized)
        sessions[index] = bound
        selectedSession = bound
        // Статус «открыт проект»: выбираем workspace проекта без сброса сессии.
        if let workspace = workspaces.first(where: {
            ChatSession.normalizedPath($0.path) == normalized
        }) {
            if selectedWorkspace?.id != workspace.id {
                selectedWorkspace = workspace
                defaults.set(workspace.id, forKey: "com.mycoder.lastWorkspaceID")
            }
        }
        _ = DatabaseBridge.shared.bindSessionToProject(
            sessionId: sessionID,
            projectId: normalized,
            directory: normalized
        )
        return normalized
    }
}
