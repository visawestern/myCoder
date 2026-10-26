import Foundation

/// Kimi model menu behavior (audits 2026-09-08/09): clicking "K3"/"K3 Swarm"
/// navigates to the Agent product surface (`/agent…`) AND commits the choice
/// there (live: label reads "K3" on `/agent?chat_enter_method=change_model`,
/// same `div.chat-input-editor` + `.send-button-container` composer contract
/// as chat). Those models live ONLY on /agent — navigating "back" to the
/// chat surface resets the choice to Fast and blocks the send. Conversely the
/// Fast model lives on the chat surface; /agent with Fast selected is drift.
/// Surface checks are therefore MODEL-AWARE for Kimi.
enum WebChatSurfaceLogic {
    /// Kimi models whose home surface is Kimi Agent (/agent…), exact match,
    /// case-insensitive. Verified live 2026-09-09 via the model menu.
    static let kimiAgentModels: [String] = ["K3", "K3 Swarm"]

    /// True when the selected model lives on Kimi Agent.
    static func isKimiAgentModel(_ model: String, vendor: WebChatVendor) -> Bool {
        guard vendor == .kimi else { return false }
        let wanted = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return kimiAgentModels.contains { $0.lowercased() == wanted }
    }

    /// True when the URL is a page the send flow supports: the provider host
    /// and, for Kimi, the surface matching the selected model (chat surface
    /// for Fast, /agent for K3/K3 Swarm).
    static func isChatSurface(urlString: String,
                              chatURL: String,
                              vendor: WebChatVendor,
                              selectedModel: String = "") -> Bool {
        guard let url = URL(string: urlString),
              let chat = URL(string: chatURL),
              let host = url.host?.lowercased(),
              let chatHost = chat.host?.lowercased(),
              host == chatHost else { return false }
        if vendor == .kimi {
            let onAgent = url.path.lowercased().hasPrefix("/agent")
            // /agent is the RIGHT surface for agent models, drift otherwise.
            return onAgent == isKimiAgentModel(selectedModel, vendor: vendor)
        }
        return true
    }

    /// The surface URL a turn must start on for the selected model: the
    /// plain chat URL, except Kimi agent models (K3/K3 Swarm) which live on
    /// the /agent surface of the same host (live 2026-09-09).
    static func targetSurfaceURL(chatURL: String,
                                 vendor: WebChatVendor,
                                 selectedModel: String = "") -> String {
        guard vendor == .kimi,
              isKimiAgentModel(selectedModel, vendor: vendor),
              let chat = URL(string: chatURL),
              let scheme = chat.scheme,
              let host = chat.host else { return chatURL }
        return "\(scheme)://\(host)/agent"
    }

    /// True when a menu interaction kept the provider host but landed on a
    /// surface that does NOT match the selected model (live: Kimi model menu
    /// click "K3" kept www.kimi.ai but navigated to /agent*). Scoped
    /// narrowly: a host change is NOT a detour (region setups legitimately
    /// differ), and an empty or unparseable chatURL (custom vendors) never
    /// triggers a return trip.
    static func isProductDetour(afterURL: String,
                                chatURL: String,
                                vendor: WebChatVendor,
                                selectedModel: String = "") -> Bool {
        guard !afterURL.isEmpty,
              let after = URL(string: afterURL),
              let chat = URL(string: chatURL),
              let afterHost = after.host?.lowercased(),
              let chatHost = chat.host?.lowercased(),
              afterHost == chatHost else { return false }
        if vendor == .kimi {
            let onAgent = after.path.lowercased().hasPrefix("/agent")
            return onAgent != isKimiAgentModel(selectedModel, vendor: vendor)
        }
        return false
    }
}
