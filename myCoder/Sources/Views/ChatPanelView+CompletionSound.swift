import SwiftUI
import AppKit

extension ChatPanelView {
    /// Играет звук завершения хода, если чат действительно закончил работу:
    /// нет активной цели, ошибки, остановки и ожидания действия пользователя.
    /// См. `CompletionSoundLogic` (запрос 2026-11-13). Вызов идемпотентен —
    /// `CompletionSoundPlayer` дедуплицирует дубли одного хода.
    @MainActor
    func playCompletionSoundIfIdle(endedWithError: Bool = false,
                                   stoppedByUser: Bool = false,
                                   awaitingUserInput: Bool = false) {
        let context = CompletionTurnContext(
            completed: true,
            activeGoalRunning: CompletionSoundLogic.hasActiveGoal(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            ),
            endedWithError: endedWithError,
            stoppedByUser: stoppedByUser,
            awaitingUserInput: awaitingUserInput
        )
        if CompletionSoundLogic.decide(context) == .play {
            CompletionSoundPlayer.shared.playIfNeeded()
        }
    }
}
