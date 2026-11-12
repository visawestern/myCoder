import SwiftUI
import AppKit

/// UI side of the project-less write gate.
///
/// Input: a suggested project folder name and the chat that attempted the
/// write. Output: the created project root, or nil when the user declined.
///
/// Purpose: a chat without a project must not write into the home folder. The
/// user is asked to create a project in a separate folder; on confirmation the
/// project is registered, a new chat is opened there, and the current turn
/// stops with a visible notice. The tool itself is never executed by the old
/// chat — `ProjectlessWriteLogic` owns the refusal text.
///
/// Dependencies: `AppState` (project creation + chat selection), `MessageStore`
/// (notice) and `TurnNoticeBuilder`.
extension ChatPanelView {

    /// Asks for a project folder, creates it and opens a new chat there.
    ///
    /// - Parameters:
    ///   - suggestedName: folder name derived from the requested file.
    ///   - sessionID: chat whose turn triggered the write; the notice is
    ///     written there even if the user already switched chats.
    /// - Returns: the new project root, or nil when the user cancelled.
    @MainActor
    func promptCreateProjectForFileWrite(suggestedName: String,
                                         sessionID: String?) async -> String? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.t(AppLocalizationKey.locProjectlessWriteTitle)
        alert.informativeText = L.t(AppLocalizationKey.locProjectlessWriteBody)
        alert.addButton(withTitle: L.t(AppLocalizationKey.locProjectlessWriteCreate))
        alert.addButton(withTitle: L.t(AppLocalizationKey.locCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L.t(AppLocalizationKey.locProjectlessWriteCreate)
        panel.message = L.t(AppLocalizationKey.locProjectlessWriteFolder)
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let path = url.path
        appState.createNewProject(name: url.lastPathComponent, path: path)
        let workspace = appState.workspaces.first {
            ChatSession.normalizedPath($0.path) == ChatSession.normalizedPath(path)
        }
        if let workspace {
            appState.startNewTask(in: workspace)
        }
        let notice = L.t(AppLocalizationKey.locProjectlessWriteNotice, path)
        messageStore.append(TurnNoticeBuilder.warningNotice(notice), to: sessionID)
        return path
    }
}
