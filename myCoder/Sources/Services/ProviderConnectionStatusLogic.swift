import Foundation

enum ProviderConnectionStatusLogic {
    static func endpointLabel(
        selectedID: String,
        serverProviderIDs: [String],
        serverConnected: Bool,
        serverHost: String,
        serverPort: Int
    ) -> String {
        guard !selectedID.isEmpty else { return "" }
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard serverConnected,
              serverProviderIDs.contains(selectedID),
              !host.isEmpty,
              (1...65535).contains(serverPort) else {
            return selectedID
        }
        return "\(host):\(serverPort)"
    }

    static func isConnected(
        selectedID: String,
        serverProviderIDs: [String],
        serverConnected: Bool,
        autoFreeID: String,
        autoFreeReady: Bool,
        webConnected: Bool?,
        localEnabled: Bool,
        customReady: Bool,
        remembered: Bool?
    ) -> Bool {
        guard !selectedID.isEmpty else { return false }
        if serverProviderIDs.contains(selectedID) {
            return serverConnected
        }
        if selectedID == autoFreeID {
            return autoFreeReady
        }
        if selectedID.hasPrefix("web:") {
            return webConnected == true
        }
        if let remembered {
            return remembered
        }
        if localEnabled || customReady {
            return true
        }
        return false
    }
}
