import Foundation
import SwiftUI
import AppKit

/// Журнал и этапы подготовки контекста.
extension AppState {
    /// True while the SELECTED chat compiles its point context
    /// (user directive D1: the loader says "собираем точечный контекст").
    var isCompilingContext: Bool {
        ContextSessionStatusLogic.isCompiling(
            compiling: contextCompilingSessionIDs,
            selectedSessionID: selectedSession?.id
        )
    }

    /// Current stage line of the SELECTED chat.
    var contextPreparationStage: String {
        ContextSessionStatusLogic.stage(
            stages: contextPreparationStages,
            selectedSessionID: selectedSession?.id
        )
    }

    /// Context-assembly journal of the SELECTED chat.
    var contextAssemblyLog: ContextAssemblyLogLogic.Log {
        ContextSessionStatusLogic.log(
            logs: contextAssemblyLogs,
            selectedSessionID: selectedSession?.id
        )
    }

    /// Begin a context-assembly run for one chat.
    ///
    /// Вход: `sessionID` — чат, которому принадлежит отправка.
    /// Выход: нет; повторный вызов идемпотентен.
    /// Зависимости: `ContextSessionStatusLogic.key`.
    func beginContextCompilation(sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        contextCompilingSessionIDs.insert(key)
    }

    /// End a context-assembly run for one chat.
    ///
    /// Вход: `sessionID` — чат, в котором сборка завершилась.
    /// Выход: нет.
    /// Зависимости: `ContextSessionStatusLogic.key`.
    func endContextCompilation(sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        contextCompilingSessionIDs.remove(key)
    }

    /// Store the current stage line for one chat.
    ///
    /// Вход: `line` — текст стадии; `sessionID` — чат сборки.
    /// Выход: нет.
    /// Зависимости: `ContextSessionStatusLogic.key`.
    func setContextStage(_ line: String, sessionID: String?) {
        let key = ContextSessionStatusLogic.key(sessionID)
        guard !key.isEmpty else { return }
        contextPreparationStages[key] = line
    }

    func loadSessionContext(sessionID: String) async {
        let context = await MainActor.run { () -> (directory: String?, summary: MimoSessionSummary?) in
            let session = self.sessions.first(where: { $0.id == sessionID }) ?? self.selectedSession
            let directory = SessionContextLoader.gitDirectoryPath(
                workspacePath: self.selectedWorkspace?.path,
                sessionDirectory: session?.directory
            )
            return (directory, session?.gitSummary)
        }

        let localResult = await refreshGitFromLocal(directory: context.directory)

        let shouldFetchRemote = SessionContextLoader.shouldFetchRemoteGit(
            localChangeCount: localResult.changeCount,
            localGitFailed: localResult.failed
        )
        guard shouldFetchRemote else { return }

        do {
            let diff = try await mimoClient.vcsDiff(directory: context.directory, mode: .git)
            let totals = SessionContextLoader.gitTotals(vcsFiles: diff.files, sessionSummary: context.summary)
            await MainActor.run {
                self.vcsChanges = diff.files
                self.sessionGitTotals = totals
                self.gitStatusMessage = nil
            }
        } catch {
            await MainActor.run {
                if let summary = context.summary {
                    self.sessionGitTotals = SessionContextLoader.gitTotals(vcsFiles: [], sessionSummary: summary)
                }
            }
            print("Failed to load session git context: \(error)")
        }
    }
}
