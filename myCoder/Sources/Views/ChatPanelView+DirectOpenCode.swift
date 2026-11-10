import SwiftUI
import AppKit

extension ChatPanelView {
    /// One turn against a local `opencode serve` instance (OC-3): SSE stream
    /// with a blocking fallback, then persistence of the final text.
    func runOpenCodeServeDirectTurn(
        baseURL: String,
        headers: [String: String],
        providerID: String,
        model: String,
        assistantID: String,
        earlyPreparedSessionID: String?,
        modelText: String
    ) async throws {
            let chatKey = earlyPreparedSessionID ?? assistantID
            await MainActor.run {
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = SendStatusText.waitingForResponse(modelID: model, providerName: "OpenCode")
                }
            }
            let sid = OpenCodeServeSessionStore.shared.sessionID(for: chatKey)
            var streamed = ""
            var promptAcceptedSID: String? = nil
            do {
                // Prefer SSE streaming (prompt_async + /event); fall back
                // to the blocking call when the stream yields nothing
                // (e.g. older serve without prompt_async).
                let (streamSID, stream) = try await OpenCodeServeClient.streamSend(
                    baseURL: baseURL, headers: headers, modelID: model,
                    text: modelText, providerID: providerID, sessionID: sid
                )
                promptAcceptedSID = streamSID
                OpenCodeServeSessionStore.shared.remember(sessionID: streamSID, for: chatKey)
                for try await event in stream {
                    streamed += event.text
                    let snapshot = streamed
                    await MainActor.run {
                        self.messageStore.update(id: assistantID) { msg in
                            msg.content = snapshot
                            msg.isStreaming = true
                        }
                    }
                }
            } catch {
                guard !streamed.isEmpty else {
                    throw error
                }
            }
            if streamed.isEmpty {
                // The prompt may already be processing server-side, so a
                // blind re-send would duplicate the user message: read back
                // the session first, and re-send only when the server has
                // nothing for it.
                if let activeSID = promptAcceptedSID,
                   let recovered = await OpenCodeServeClient.fetchLastAssistantText(
                    baseURL: baseURL, headers: headers, sessionID: activeSID
                   ) {
                    OpenCodeServeSessionStore.shared.remember(sessionID: activeSID, for: chatKey)
                    streamed = recovered
                } else {
                    let result = try await RequestRetryPolicy.withRetries {
                        try await OpenCodeServeClient.send(
                            baseURL: baseURL, headers: headers, modelID: model,
                            text: modelText, providerID: providerID, sessionID: sid
                        )
                    }
                    OpenCodeServeSessionStore.shared.remember(sessionID: result.sessionID, for: chatKey)
                    streamed = result.content
                }
            }
            let finalText = streamed
            await MainActor.run {
                self.appState.isLoading = false
                self.appState.isStreaming = false
                self.streamingText = ""
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = finalText
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                self.currentAssistantMessageID = nil
            }
            return
    }
}
