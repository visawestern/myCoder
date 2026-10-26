import Foundation

enum SessionSendLogic {
    /// Returns true when a new server session must be created before sending.
    static func shouldCreateNewSession(selectedSessionID: String?) -> Bool {
        guard let id = selectedSessionID else { return true }
        return id.isEmpty
    }

    /// Resolves which session ID to use for the outgoing message.
    static func resolvedSessionID(selectedSessionID: String?, newlyCreatedID: String) -> String {
        if let id = selectedSessionID, !id.isEmpty {
            return id
        }
        return newlyCreatedID
    }

    /// Maps agent mode to MiMo Serve agent field.
    static func sendMode(for agentMode: AgentMode) -> String {
        switch agentMode {
        case .build: return "build"
        case .plan: return "plan"
        case .compose: return "compose"
        }
    }

    static func buildSendOptions(
        agentMode: AgentMode,
        selectedVariant: String?,
        modelID: String,
        selectedProviderID: String,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider],
        messageID: String? = nil,
        accessLevel: AccessLevel? = nil,
        localProviderIDs: [String] = []
    ) -> MessageSendOptions {
        let agent = sendMode(for: agentMode)
        MyCoderAPIServer.appendLog("📍 buildSendOptions: selectedProviderID=\(selectedProviderID), modelID=\(modelID)")
        // Web providers are not part of the myCoder Serve provider catalog.
        // Preserve the explicit `web:<config-id>` so the serve-only resolver
        // does not erase it and trigger "Select a provider" before routing.
        // Same for local provider ids (Ollama/OpenCode/ACP): they never appear
        // in the serve catalog, and erasing them breaks local sends.
        let providerID: String?
        if selectedProviderID.hasPrefix("web:") || selectedProviderID == MyCoderAutoFreeProvider.builtInID
            || localProviderIDs.contains(selectedProviderID) {
            providerID = selectedProviderID
            MyCoderAPIServer.appendLog("📍 buildSendOptions: preserved providerID=\(providerID ?? "nil")")
        } else {
            providerID = ProviderSettingsLogic.resolveProviderID(
                for: modelID,
                selectedProviderID: selectedProviderID,
                in: providers,
                customProviders: customProviders
            )
            MyCoderAPIServer.appendLog("📍 buildSendOptions: resolved providerID=\(providerID ?? "nil")")
        }
        let variant = ProviderSettingsLogic.normalizedVariant(
            selectedVariant,
            for: modelID,
            in: providers,
            providerID: providerID,
            customProviders: customProviders
        )

        return MessageSendOptions(
            agent: agent,
            modelID: modelID.isEmpty ? nil : modelID,
            providerID: providerID,
            variant: variant,
            messageID: messageID,
            permission: accessLevel.flatMap { AccessLevelPermissionLogic.permissionPatch(for: $0) as? [String: String] }
        )
    }

    static func restoreSelections(from messages: [MimoMessageResponse]) -> SessionSendSelections? {
        guard let lastUser = messages.reversed().first(where: { $0.info?.role == "user" }) else {
            return nil
        }
        let modelID = lastUser.info?.modelID ?? lastUser.info?.model?.modelID
        let providerID = lastUser.info?.providerID ?? lastUser.info?.model?.providerID
        return SessionSendSelections(
            agentMode: agentMode(from: lastUser.info?.agent),
            providerID: providerID,
            modelID: modelID,
            variant: lastUser.info?.variant ?? lastUser.info?.model?.variant
        )
    }

    static func agentMode(from agent: String?) -> AgentMode? {
        switch agent?.lowercased() {
        case "build": return .build
        case "plan": return .plan
        case "compose": return .compose
        default: return nil
        }
    }

    /// Reconciles local assistant message ID with server-assigned ID.
    static func reconcileAssistantMessageID(localID: String?, serverID: String) -> String {
        if let local = localID, !local.isEmpty, local != serverID {
            return serverID
        }
        return serverID
    }

    /// The local placeholder remains the UI/update key; the server-assigned
    /// ID is stored on the message for reconciliation. Switching the live key
    /// to the server ID made every following part update miss the local store,
    /// leaving the bubble streaming forever and its reasoning spoiler open.
    static func assistantUpdateID(localID: String?, serverID: String) -> String {
        if let local = localID, !local.isEmpty { return local }
        return serverID
    }

    static func assistantResponse(from messages: [MimoMessageResponse]) -> MimoMessageResponse? {
        messages.last { $0.info?.role == "assistant" }
    }

    static func shouldAwaitSSE(
        responseMessages: [MimoMessageResponse],
        hasPendingQuestion: Bool
    ) -> Bool {
        !hasPendingQuestion && assistantResponse(from: responseMessages) == nil
    }

    static func workedDurationLabel(since start: Date, until end: Date = Date()) -> String {
        let seconds = max(1, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "Worked for \(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "Worked for \(minutes)m \(seconds % 60)s" }
        let hours = minutes / 60
        return "Worked for \(hours)h \(minutes % 60)m"
    }
}

struct SessionSendSelections: Equatable {
    let agentMode: AgentMode?
    let providerID: String?
    let modelID: String?
    let variant: String?
}

/// Visible "waiting/thinking" text shown in the assistant bubble while a
/// provider is answering (Round 8 P4 — the OpenAI-compatible path used to
/// show an empty streaming bubble with no indication for up to 120 s).
enum SendStatusText {
    /// Status line while the provider is processing the request.
    static func waitingForResponse(modelID: String, providerName: String?) -> String {
        let name = providerName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name {
            if model.isEmpty {
                return "Waiting for \(name) to respond…"
            }
            return "Waiting for \(name) (\(model)) to respond…"
        }
        if model.isEmpty {
            return "Waiting for the provider to respond…"
        }
        return "Waiting for \(model) to respond…"
    }

    /// Placeholder for an empty streaming bubble before any text arrives.
    static func thinkingPlaceholder(modelID: String) -> String {
        "Thinking… (\(modelID))"
    }
}
