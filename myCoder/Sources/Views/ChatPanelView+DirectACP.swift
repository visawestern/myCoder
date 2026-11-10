import SwiftUI
import AppKit

extension ChatPanelView {
    /// One non-streaming ACP turn. Returns `true` when an ACP client handled
    /// the request, `false` when the turn must continue down the serve path.
    func runACPDirectTurn(
        route: SendRoute,
        localProviders: [LocalProviderConfig],
        assistantID: String,
        modelText: String,
        files: [FileInfo],
        images: [ClipboardImage],
        agentModeOverride: AgentMode?,
        text: String
    ) async throws -> Bool {
        // ── ACP provider branch ──────────────────────────────
        // Custom ACP providers (custom.type == .acp) and auto-detected
        // local ACP providers both land here via the resolver's `.acp`
        // route. The old code only handled the custom case, so a detected
        // ACP provider fell through into the serve branch and never sent.
        let acpClient: ACPClient?
        if case .acp = route,
           let local = localProviders.first(where: { $0.id == appState.selectedProviderID && $0.isEnabled }) {
            acpClient = ACPClient(baseURLString: local.apiBaseURL)
        } else {
            acpClient = appState.isSelectedACPProvider ? appState.acpClient : nil
        }
        if let acpClient = acpClient {
            // Build ACP request messages from user text + files
            let acpMessages = buildACPMessages(text: modelText, files: files, images: images)
            let acpAgent = SessionSendLogic.sendMode(for: agentModeOverride ?? appState.agentMode)
            let acpVariant = appState.selectedVariant.isEmpty ? nil : appState.selectedVariant

            // Non-streaming send via ACP client (E06: parameters must
            // actually reach the ACP model, they used to be dropped).
            // Empty responses are transient: retry before surfacing.
            let response = try await RequestRetryPolicy.withRetries {
                try await acpClient.sendChatCompletion(
                    messages: acpMessages,
                    model: appState.selectedModel,
                    agent: acpAgent,
                    variant: acpVariant,
                    parameters: ModelCallParametersStore.parameters(for: appState.effectiveSelectedModel()),
                    stream: false
                )
            }

            // Convert ACP response to message text and reject a blank completion.
            let responseText = response.choices.first?.message.content ?? ""
            guard ProviderResponseValidationLogic.hasVisibleContent(responseText) else {
                throw ACPError.emptyResponse
            }
            let reasoningText = response.choices.first?.message.reasoning
            let acpUsage = response.usage.map {
                UsageCapture(acpUsage: $0, modelID: response.model,
                             providerID: appState.selectedProviderID.isEmpty ? "acp" : appState.selectedProviderID)
            }

            await MainActor.run {
                self.appState.isLoading = false
                self.appState.isStreaming = false
                self.streamingText = ""
                self.messageStore.update(id: assistantID) { msg in
                    msg.content = responseText
                    msg.reasoning = reasoningText ?? ""
                    msg.usage = acpUsage
                    msg.isFinished = true
                    msg.isStreaming = false
                }
                self.currentAssistantMessageID = nil
                // No session for ACP — task complete is still useful
                self.appState.notificationService.taskCompleted(
                    sessionTitle: String(text.prefix(50)),
                    sessionID: assistantID
                )
            }
            return true
        }
        return false
    }
}
