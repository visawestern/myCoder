import SwiftUI
import AppKit

extension ChatPanelView {
    /// Handles a failed direct turn: busy-session retry, transport-failure
    /// bookkeeping and the user-facing error bubble. Extracted from
    /// `performDirectSend` to keep that function inside the module budget.
    func handleDirectSendError(
        _ error: Error,
        assistantID: String,
        retryCount: Int,
        sendSessionID: String?,
        selectedID: String?,
        messageID: String,
        text: String,
        files: [FileInfo],
        images: [ClipboardImage],
        agentModeOverride: AgentMode?,
        route: SendRoute
    ) async {
            if case MimoServeError.sessionBusy = error {
                await MainActor.run {
                    self.messageStore.update(id: assistantID) { msg in
                        msg.content = retryCount < 3 ? "Session busy, aborting and retrying..." : "Session busy after \(retryCount + 1) attempts, giving up."
                        msg.isStreaming = true
                    }
                    self.appState.notificationService.sessionBusy()
                }
                if let sessionID = sendSessionID ?? selectedID,
                   !sessionID.isEmpty {
                    let currentPlan = SessionBusyRetryLogic.RetryPlan(
                        retryCount: retryCount,
                        sessionID: sessionID,
                        assistantMessageID: assistantID,
                        messageID: messageID
                    )
                    if let nextPlan = SessionBusyRetryLogic.nextPlan(
                        from: currentPlan,
                        isCancelled: Task.isCancelled
                    ) {
                        guard !Task.isCancelled else { return }
                        try? await appState.mimoClient.abortSession(id: sessionID)
                        guard !Task.isCancelled else { return }
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        await sendDirectly(
                            text: text,
                            files: files,
                            images: images,
                            agentModeOverride: agentModeOverride,
                            retryCount: nextPlan.retryCount,
                            retryPlan: nextPlan
                        )
                        return
                    }
                }
            }
            let isServeRoute: Bool
            if case .mimoServe = route {
                isServeRoute = true
            } else {
                isServeRoute = false
            }
            let serveDisconnected = ServeTransportFailureLogic.shouldMarkServerDisconnected(
                isServeRoute: isServeRoute,
                error: error
            )
            let userFacingError = serveDisconnected
                ? ServeTransportFailureLogic.disconnectedMessage
                : "Error: \(error.localizedDescription)"
            await MainActor.run {
                self.serveTimeoutTask?.cancel()
                self.serveTimeoutTask = nil
                self.appState.isLoading = false
                self.appState.isStreaming = false
                self.sseClient.disconnect()
                if serveDisconnected {
                    self.appState.serverConnected = false
                    self.appState.notificationService.serverDisconnected()
                }
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = userFacingError
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                self.appState.scheduleGitRefresh(sessionID: sendSessionID)
            }
    }
}
