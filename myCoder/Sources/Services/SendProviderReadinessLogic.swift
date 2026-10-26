import Foundation

enum SendProviderReadinessLogic {
    struct CustomProviderState: Equatable {
        let id: String
        let isEnabled: Bool
        let requiresAPIKey: Bool
        let hasAPIKey: Bool
    }

    static func connectionValidationError(
        serverConnected: Bool,
        selectedProviderID: String,
        autoFreeID: String = "mycoder-auto-free",
        autoFreeReady: Bool = true,
        customProviders: [CustomProviderState],
        localProviderIDs: [String],
        webProviderIDs: [String],
        serverProviderIDs: [String],
        webConnected: Bool?
    ) -> String? {
        let selected = selectedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            return genericProviderError
        }

        if selected == autoFreeID {
            return autoFreeReady
                ? nil
                : "OpenCode Zen is unavailable. Refresh the anonymous OpenCode free catalog or choose another provider."
        }

        if let webID = webID(from: selected) {
            guard webProviderIDs.contains(webID) else { return genericProviderError }
            guard webConnected != false else {
                return "The selected web provider is not connected. Reconnect it in Settings before sending."
            }
            return nil
        }

        if localProviderIDs.contains(selected) { return nil }

        if !serverConnected && serverProviderIDs.contains(selected) {
            return "myCoder Serve is not running or disconnected. Start or reconnect myCoder Serve before sending."
        }

        if let custom = customProviders.first(where: { $0.id == selected && $0.isEnabled }) {
            if custom.requiresAPIKey && !custom.hasAPIKey {
                return "This provider requires an API key. Add it in Settings."
            }
            return nil
        }

        if serverConnected && (serverProviderIDs.isEmpty || serverProviderIDs.contains(selected)) {
            return nil
        }
        return genericProviderError
    }

    static func modelValidationID(selectedModel: String, effectiveModel: String) -> String {
        let effective = effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effective.isEmpty { return effective }
        return selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func webID(from providerID: String) -> String? {
        guard providerID.hasPrefix("web:") else { return nil }
        let value = String(providerID.dropFirst(4))
        return value.isEmpty ? nil : value
    }

    private static let genericProviderError =
        "No provider is ready. Connect the local agent, add a custom provider, configure a local model, or connect a web provider."
}
