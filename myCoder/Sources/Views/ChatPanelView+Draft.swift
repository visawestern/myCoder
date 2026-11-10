import SwiftUI
import AppKit

extension ChatPanelView {
// MARK: - Draft persistence
    func loadDraft(for sessionID: String?) {
        guard let sessionID = sessionID, !sessionID.isEmpty else {
            messageText = ""
            return
        }
        Task {
            do {
                let draft = try DatabaseManager.shared.getSessionDraftText(sessionId: sessionID)
                await MainActor.run {
                    messageText = draft ?? ""
                }
            } catch {
                // Ignore draft load errors silently
            }
        }
    }
    
    func saveDraft(_ text: String) {
        guard let sessionID = messageStore.currentSessionID, !sessionID.isEmpty else { return }
        Task {
            do {
                try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: text.isEmpty ? nil : text)
            } catch {
                // Ignore draft save errors silently
            }
        }
    }
    
    func clearDraft() {
        guard let sessionID = messageStore.currentSessionID, !sessionID.isEmpty else { return }
        Task {
            do {
                try DatabaseManager.shared.setSessionDraftText(sessionId: sessionID, text: nil)
            } catch { }
        }
    }
}
