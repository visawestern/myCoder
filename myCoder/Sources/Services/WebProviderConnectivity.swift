import Foundation

/// Connectivity + selection logic for web providers in the chat input
/// (plan Раздел 13 п.4). A web provider counts as "connected" ONLY after a
/// session (cookies) has been captured — not merely added.
enum WebProviderConnectivity {
    /// Whether a web provider is connected: cookies persisted (non-empty and
    /// non-expired). Legal acknowledgement is not a runtime connectivity gate.
    static func isConnected(_ config: WebProviderConfig,
                            homeDirectory: URL,
                            now: Date = Date()) -> Bool {
        let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
        guard let store = WebSessionManager.restore(providerId: config.id,
                                                    homeDirectory: homeDirectory,
                                                    sessionID: sessionID) else {
            return false
        }
        guard !store.cookies.isEmpty else { return false }
        guard !WebSessionManager.isExpired(store, now: now) else { return false }
        // Audit 2026-09-08: anonymous cookies (analytics/theme) are not a
        // login. A captured session must contain at least one vendor auth
        // cookie, otherwise a logged-out page snapshot reported "connected"
        // and every send failed only at automation time (live: Kimi with 7
        // analytics cookies and no kimi-auth).
        return hasAuthCookie(vendor: config.vendor, cookies: store.cookies)
    }

    /// Vendor-specific authentication cookie names observed on the live sites
    /// (audit 2026-09-08). Any one match is enough.
    static func hasAuthCookie(vendor: WebChatVendor, cookies: [BrowserCookie]) -> Bool {
        let required: [String]
        switch vendor {
        case .kimi: required = ["kimi-auth", "access_token", "refresh_token"]
        case .qwen: required = ["token", "chatqa_uat", "tongyi_sso_ticket"]
        case .chatgpt: required = ["__Secure-next-auth.session-token"]
        case .claude: required = ["sessionKey", "__Secure-next-auth.session-token", "kimi-auth"]
        case .custom: return !cookies.isEmpty
        }
        return cookies.contains { cookie in
            required.contains { cookie.name == $0 || cookie.name.hasPrefix($0) }
        }
    }

    /// Chat-input provider options for connected web providers, so they appear
    /// alongside local/custom providers in the send-message provider selector.
    static func providerOptions(_ configs: [WebProviderConfig],
                               homeDirectory: URL,
                               now: Date = Date()) -> [ProviderOption] {
        configs
            .filter { isConnected($0, homeDirectory: homeDirectory, now: now) }
            .filter { !models(for: $0).isEmpty }
            .map { ProviderOption(id: "web:\($0.id)", name: "🌐 \($0.displayName)",
                                  isCustom: true, isConnected: true) }
    }

    /// The models offered by a web provider. Only live-discovered or explicitly
    /// configured models are valid; catalog lists are not used as guesses for a
    /// changing third-party UI.
    static func models(for config: WebProviderConfig) -> [String] {
        config.allModels
    }

    /// Whether the given provider option id refers to a web provider.
    static func isWebProviderID(_ id: String) -> Bool { id.hasPrefix("web:") }

    /// Extract the WebProviderConfig id from an option id.
    static func configID(fromOptionID id: String) -> String? {
        guard id.hasPrefix("web:") else { return nil }
        return String(id.dropFirst("web:".count))
    }

    /// Connection summary shown once connected (plan Раздел 13 п.4).
    static func connectionSummary(_ config: WebProviderConfig, connected: Bool) -> String {
        guard connected else { return "Not connected — log in to capture a session." }
        let modelCount = models(for: config).count
        let runtime = WebTransportRuntimeLogic.label(for: config.transport)
        return "\(runtime) · \(modelCount) models · delay \(config.toolCallDelayMs)ms"
    }
}
