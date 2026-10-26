import Foundation

/// Resolves how an outgoing message should be delivered based on the currently
/// selected provider, so sending adapts to web / local / custom / ACP / serve
/// providers instead of only the MiMo Serve path (fixes the "message sends
/// nothing" bug). Pure/testable — the send code executes the resolved route.
enum SendRoute: Equatable {
    /// ACP-compatible provider (handled by ACPClient).
    case acp
    /// Built-in MiMo Serve transport.
    case mimoServe
    /// OpenAI-compatible HTTP endpoint (Ollama/OpenCode/custom OpenAI providers).
    case openAICompatible(baseURL: String, apiKey: String?, model: String)
    /// Local `opencode serve` session REST API (verified live: it does NOT
    /// speak OpenAI /v1 — POST /session then POST /session/:id/message).
    /// Headers carry basic auth when the serve instance requires it.
    case openCodeServe(baseURL: String, headers: [String: String], providerID: String, model: String)
    /// Web-chat provider driven through the browser (WebChatDriver).
    case web(configID: String)
    /// Built-in myCoder Auto Free provider (direct to OpenCode Zen).
    case autoFree
    /// Nothing usable selected.
    case none
}

enum SendRouteResolver {
    /// Determine the route for the selected provider id.
    static func route(
        selectedProviderID: String,
        selectedModel: String,
        serverConnected: Bool,
        isACP: Bool,
        customProviders: [CustomProvider],
        localProviders: [LocalProviderConfig],
        webProviderIDs: [String]
    ) -> SendRoute {
        // 0) Built-in myCoder Auto Free provider (always present).
        if selectedProviderID == MyCoderAutoFreeProvider.builtInID {
            return .autoFree
        }
        // 1) Web provider (option id "web:<id>").
        if let webID = WebProviderConnectivity.configID(fromOptionID: selectedProviderID),
           webProviderIDs.contains(webID) {
            return .web(configID: webID)
        }
        // 2) Local provider (Ollama/OpenCode/MiMo CLI/ACP) → OpenAI-compatible
        //    HTTP, except ACP which keeps its own route (an ACP server speaks
        //    /acp/v1, not OpenAI /v1/chat/completions).
        if let local = localProviders.first(where: { $0.id == selectedProviderID && $0.isEnabled }) {
            switch local.kind {
            case .ollama, .openAICompatible:
                return .openAICompatible(baseURL: "\(local.apiBaseURL)/v1", apiKey: nil, model: selectedModel)
            case .openCode:
                return .openCodeServe(baseURL: local.apiBaseURL, headers: local.authHeaders(),
                                      providerID: local.openCodeProviderID, model: selectedModel)
            case .localAgent:
                return .openAICompatible(baseURL: local.apiBaseURL, apiKey: nil, model: selectedModel)
            case .acp:
                return .acp
            }
        }
        // 3) ACP provider.
        if isACP { return .acp }
        // 4) Custom cloud provider (OpenAI-compatible) selected while serve is off
        //    or the provider has its own endpoint/key. The key may live in the
        //    Keychain while the in-memory copy carries it too (see AppState
        //    addCustomProvider/updateCustomProvider); resolve via the secure
        //    accessor so a freshly saved key routes correctly without a restart
        //    (audit ARCH-04).
        if let custom = customProviders.first(where: { $0.id == selectedProviderID && $0.isEnabled }) {
            let normalizedKey = (custom.getSecureAPIKey() ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .openAICompatible(baseURL: custom.baseURL,
                                     apiKey: normalizedKey.isEmpty ? nil : normalizedKey,
                                     model: selectedModel)
        }
        // 5) MiMo Serve when connected (server-provided providers).
        if serverConnected { return .mimoServe }
        return .none
    }

    /// Whether a route is ready to send without the MiMo Serve connection.
    static func requiresServer(_ route: SendRoute) -> Bool {
        if case .mimoServe = route { return true }
        return false
    }
}

/// Explicit handling for routes that must NOT fall through into the serve
/// branch (Round 8 P3 — `.none` used to silently call createSession).
enum SendRouteGuard {
    /// Returns a user-facing error for a `.none` route (the view shows it and
    /// stops instead of falling through into the serve branch). All other
    /// routes are handled by their own branch, so they yield nil.
    static func errorMessage(for route: SendRoute, serverConnected: Bool) -> String? {
        guard case .none = route else { return nil }
        if serverConnected {
            return "No provider is ready. Choose a provider or model before sending."
        }
        return "No provider is ready. Connect a local agent, add a custom provider, configure a local model, or connect a web provider."
    }

    /// Message shown when a web route's stored config no longer exists
    /// (deleted after selection) — Round 8 R2: the old flow fell through into
    /// the serve branch and produced a confusing error.
    static func webConfigMissingMessage(configID: String) -> String? {
        "The web provider \"\(configID)\" is no longer configured. Reconnect it in Settings before sending."
    }
}
