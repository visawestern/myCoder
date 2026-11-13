import Foundation

/// What the top-bar Browser button should do on the next click.
///
/// - `show`: open the browser panel for the resolved web provider.
/// - `hide`: the panel is visible, so the click hides it (the AntiBrowser tab
///   and its login/stream stay alive).
enum WebBrowserToggleAction: Equatable {
    case show(WebBrowserPanelConfig)
    case hide
}

/// Pure resolution rules for the "Browser" hide/show button.
///
/// Input: the current panel config (nil = hidden), the selected provider
/// option id, the last web provider whose panel was shown, and all configured
/// web providers. Output: the action for the next click, or nil when there is
/// no browser to show (the button must then stay hidden).
///
/// Dependencies: `WebProviderConnectivity` for the `web:` option prefix and
/// the connected check. No UI, no AppState, no disk — fully movable/testable.
enum WebBrowserToggleLogic {

    /// Pick the web provider the button should open.
    ///
    /// Priority:
    /// 1. the provider currently selected in the composer (`web:<id>`);
    /// 2. the last web provider whose panel was shown (survives a hide);
    /// 3. the only configured provider;
    /// 4. the first connected provider;
    /// 5. the first configured provider.
    ///
    /// - Parameters:
    ///   - selectedProviderOptionID: composer provider id, may be `web:<id>`
    ///     or a local provider id.
    ///   - activeProviderID: last web provider whose panel was visible.
    ///   - configs: all configured web providers in storage order.
    /// - Returns: the matching provider, or nil when none is configured.
    static func provider(
        selectedProviderOptionID: String,
        activeProviderID: String?,
        configs: [WebProviderConfig]
    ) -> WebProviderConfig? {
        if let selectedID = WebProviderConnectivity.configID(
            fromOptionID: selectedProviderOptionID
        ), let selected = configs.first(where: { $0.id == selectedID }) {
            return selected
        }
        if let activeProviderID,
           let active = configs.first(where: { $0.id == activeProviderID }) {
            return active
        }
        if configs.count == 1 {
            return configs[0]
        }
        if let connected = configs.first(where: { WebProviderConnectivity.isConnected($0) }) {
            return connected
        }
        return configs.first
    }

    /// Resolve the next click.
    ///
    /// A visible panel always hides first: the user explicitly asked for a
    /// hide/show toggle, so one click must never be a no-op. A hidden panel
    /// re-opens for the resolved provider, bound to the CURRENT project/chat
    /// (the browser is per chat, not per provider).
    ///
    /// - Parameters:
    ///   - panelConfig: current visible panel, nil when hidden.
    ///   - selectedProviderOptionID: composer provider id.
    ///   - activeProviderID: last web provider whose panel was visible.
    ///   - configs: all configured web providers.
    ///   - projectID: current workspace id.
    ///   - chatID: current chat session id.
    /// - Returns: the action, or nil when there is no provider to open.
    static func action(
        panelConfig: WebBrowserPanelConfig?,
        selectedProviderOptionID: String,
        activeProviderID: String?,
        configs: [WebProviderConfig],
        projectID: String,
        chatID: String
    ) -> WebBrowserToggleAction? {
        if panelConfig != nil {
            return .hide
        }
        guard let provider = provider(
            selectedProviderOptionID: selectedProviderOptionID,
            activeProviderID: activeProviderID,
            configs: configs
        ) else { return nil }
        return .show(WebBrowserPanelConfig(
            providerID: provider.id,
            providerName: provider.displayName,
            projectID: projectID,
            chatID: chatID
        ))
    }
}
