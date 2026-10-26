import Foundation

enum SessionReloadLogic {
    /// Whether selecting a session should trigger a server reload and local message store reset.
    static func shouldReloadMessages(
        newSessionID: String,
        currentSessionID: String?,
        localMessageCount: Int,
        isLoading: Bool
    ) -> Bool {
        if isLoading && localMessageCount > 0 {
            return false
        }
        if newSessionID == currentSessionID && localMessageCount > 0 {
            return false
        }
        return true
    }
}
