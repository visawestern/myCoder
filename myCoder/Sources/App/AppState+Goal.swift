import Foundation
import SwiftUI
import AppKit

/// Цель сессии и отмена последнего действия.
extension AppState {
    /// Per-project undo manager, created lazily when a workspace is active.
    /// Replaces the legacy global `UndoRedoManager` (Round 7).
    var projectUndoManager: ProjectUndoManager? {
        guard let path = selectedWorkspace?.path else { return nil }
        return try? ProjectUndoManager(projectPath: path)
    }

    var currentSessionGoal: String? { selectedSession?.sessionGoal }

    /// Undo the most recent project-scoped file change and make every outcome
    /// visible. The old command discarded both the Bool result and thrown
    /// errors, leaving users unable to tell whether anything happened.
    @MainActor
    func undoLastAction() {
        guard selectedSession != nil else {
            publishShellActionNotice(
                UndoActionFeedbackLogic.message(for: .nothingToUndo),
                tone: UndoActionFeedbackLogic.tone(for: .nothingToUndo)
            )
            return
        }
        guard let projectUndoManager else {
            publishShellActionNotice(
                UndoActionFeedbackLogic.message(for: .nothingToUndo),
                tone: UndoActionFeedbackLogic.tone(for: .nothingToUndo)
            )
            return
        }
        let result: UndoActionResult
        do {
            let didUndo = try projectUndoManager.undoMostRecent(sessionId: selectedSession?.id ?? "")
            result = didUndo ? .undone : .nothingToUndo
        } catch {
            result = .failed(error.localizedDescription)
        }
        publishShellActionNotice(
            UndoActionFeedbackLogic.message(for: result),
            tone: UndoActionFeedbackLogic.tone(for: result)
        )
        if result == .undone {
            let directory = selectedWorkspace?.path
            Task { await refreshGitFromLocal(directory: directory) }
        }
    }

    @MainActor
    private func publishShellActionNotice(
        _ message: String,
        tone: UndoActionFeedbackTone
    ) {
        shellActionNotice = message
        shellActionNoticeTone = tone
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.shellActionNotice == message else { return }
                self?.shellActionNotice = nil
            }
        }
    }

    /// Set the goal on the selected session, persist in-memory and to the DB
    /// so it survives restarts (plan Раздел 5 Блок 1 п.10).
    func setCurrentSessionGoal(_ goal: String) {
        guard var session = selectedSession else { return }
        let value = SessionGoalPersistenceLogic.normalizedGoal(goal)
        session.sessionGoal = value
        selectedSession = session
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].sessionGoal = value
        }
        DatabaseBridge.shared.setSessionGoal(sessionId: session.id, goal: value)
    }
}
